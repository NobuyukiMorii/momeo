import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'package:momeo/platform/asset_pack_delivery.dart';
import 'package:momeo/stt/stt_model_provisioner.dart';
import 'package:momeo/stt/stt_transcriber.dart';

// ============================================================
// sttEngineProvider — 文字化エンジン（SttTranscriber）をアプリ全体で1つだけ持つ
//
//   エンジンの読み込みは数秒かかるため、起動時に1回だけ行い全画面で使い回す。
//   状態は AsyncValue の3状態のまま公開する:
//     loading=準備中 / data=完了 / error=失敗
//   準備ゲート（RootView・PreparationGatePage）とリスニング画面が消費する。
//
//   VAD（silero）の生成は録音セッション側の持ち物なのでここでは作らない。
//   DL の開始・再取得（fetch）もしない（fast-follow は Play が自動で始める。
//   ここは完了を待つだけで、失敗からの復帰は自動再試行が担う）。
// ============================================================

final sttEngineProvider =
    AsyncNotifierProvider<SttEngineNotifier, SttTranscriber>(
  SttEngineNotifier.new,
);

class SttEngineNotifier extends AsyncNotifier<SttTranscriber> {
  // ---------------------------------
  // 起動時の準備処理
  //   ① ネイティブ初期化 → ② モデルパス取得 → ③ (Android初回のみ) DL完了待ち
  //   → ④ エンジン生成・保持
  // ---------------------------------
  @override
  Future<SttTranscriber> build() async {
    // ① 複数回呼んでも安全
    sherpa.initBindings();

    final provisioner = SttModelProvisioner();

    // ② モデル3ファイルのパス・整合性を取得（silero の端末コピーもこの中で済む）
    var models = await provisioner.provision();

    // ③ NeMo が未到着なら、DL中に限り完了を待ってからパスを取り直す
    if (!_isNemoReady(models)) {
      await _waitForModelDownload(provisioner);
      models = await provisioner.provision();
    }

    // 待った後も揃わなければ失敗として公開する
    if (!_isNemoReady(models)) {
      throw StateError(
        'NeMo モデルが読める状態になっていません'
        '（model: ${models.nemoModel.isValid ? 'OK' : 'NG'}'
        ' / tokens: ${models.nemoTokens.isValid ? 'OK' : 'NG'}）',
      );
    }

    // ④ エンジン生成（数秒かかる本体）。破棄時にメモリから解放する。
    //    生成は同期呼び出しでメインスレッドを止めるため、所要時間を計測している
    final stopwatch = Stopwatch()..start();
    final transcriber = SttTranscriber.create(
      modelPath: models.nemoModel.path,
      tokensPath: models.nemoTokens.path,
    );
    stopwatch.stop();
    ref.onDispose(transcriber.dispose);

    if (kDebugMode) {
      debugPrint(
        '[sttEngine] エンジンの読み込みが完了しました'
        '（create: ${stopwatch.elapsedMilliseconds}ms・メインスレッド占有）',
      );
    }
    return transcriber;
  }

  // NeMo（本体・tokens）の2ファイルが正しく置いてあるか
  bool _isNemoReady(SttModels models) {
    return models.nemoModel.isValid && models.nemoTokens.isValid;
  }

  // ---------------------------------
  // Android 初回の DL 完了待ち
  //   「DL中」→ 完了 or 失敗まで待つ／「未開始・失敗で止まっている」→ 即エラー
  // ---------------------------------
  Future<void> _waitForModelDownload(SttModelProvisioner provisioner) async {
    final current = await provisioner.modelDownloadState();

    // 待たずに失敗として公開し、永久待ちを防ぐ
    if (current.phase != AssetPackPhase.downloading) {
      throw StateError(
        'NeMo モデルが未配置です（DL状態: ${current.rawStatus ?? current.phase.name}）',
      );
    }

    final finished = await provisioner.watchModelDownload().firstWhere(
          (state) =>
              state.phase == AssetPackPhase.completed ||
              state.phase == AssetPackPhase.failed,
        );
    if (finished.phase == AssetPackPhase.failed) {
      throw StateError(
        'NeMo モデルのダウンロードに失敗しました（errorCode: ${finished.errorCode}）',
      );
    }
  }
}

// ============================================================
// sttModelDownloadStateProvider — NeMo 自動DL（fast-follow）の進捗
//
//   sttEngineProvider の「準備中」だけでは DL中か読み込み中か分からないため、
//   待ち画面が併読する。iOS など自動DLが無い環境では常に ready が流れる。
// ============================================================
final sttModelDownloadStateProvider =
    StreamProvider.autoDispose<AssetPackState>((ref) async* {
  // 変化通知は動いたときしか来ないため、購読開始時点の状態をまず1回流す
  final provisioner = SttModelProvisioner();
  yield await provisioner.modelDownloadState();
  yield* provisioner.watchModelDownload();
});
