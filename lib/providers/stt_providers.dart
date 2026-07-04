import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'package:momeo/platform/asset_pack_delivery.dart';
import 'package:momeo/stt/stt_model_provisioner.dart';
import 'package:momeo/stt/stt_transcriber.dart';

// ============================================================
// sttEngineProvider — 文字化エンジン（SttTranscriber）をアプリ全体で1つだけ持つ
//
//   エンジンの読み込み（625MB をメモリに広げる・数秒）は起動のたびに必要。
//   これをアプリ起動時に1回だけ行い、以後はどの画面からも同じエンジンを使い回す。
//   （リスニング画面の持ち物にすると、画面に出入りするたび数秒固まるため）
//
//   ■ 状態の見え方（AsyncValue の3状態をそのまま使う）
//     loading … 準備中（モデルのDL待ち・メモリ読み込み中）
//     data    … 完了（中身が使えるエンジン）
//     error   … 失敗（モデル未配置・DL失敗など）
//   これを消費するのは Step 11 の待ち画面（準備中なら待つ・完了なら素通り・
//   失敗ならエラーと再試行）と、Step 10 のリスニング結線。
//
//   ■ このファイルがやらないこと
//     - 待ち画面・再試行ボタンなどの UI → Step 11
//     - VAD（silero）の生成 → 録音セッション寄りの部品なので Step 10 の録音側で作る
//       （silero ファイルの端末コピー自体は provision() が内側で済ませる）
//     - DL の開始・再取得（fetch）→ fast-follow は Play が自動で始めるので
//       ここでは「完了を待つ」だけ。始動・再試行は Step 11 に集約する。
// ============================================================

final sttEngineProvider =
    AsyncNotifierProvider<SttEngineNotifier, SttTranscriber>(
  SttEngineNotifier.new,
);

class SttEngineNotifier extends AsyncNotifier<SttTranscriber> {
  // ---------------------------------
  // 起動時に1回だけ走る準備処理
  //   ① ネイティブ初期化 → ② モデルの住所取得 → ③ (Android初回のみ) DL完了待ち
  //   → ④ エンジン生成・保持
  // ---------------------------------
  @override
  Future<SttTranscriber> build() async {
    // ① sherpa のネイティブライブラリを初期化する（複数回呼んでも安全）
    sherpa.initBindings();

    final provisioner = SttModelProvisioner();

    // ② モデル3ファイルの住所・整合性を取得する
    //    （silero のアセット → 端末コピーもこの中で済む）
    var models = await provisioner.provision();

    // ③ NeMo が未到着なら、DL中に限り完了を待ってから住所を取り直す
    //    （dev の事前配置や iOS 同梱では最初から揃うので、ここは通らない）
    if (!_isNemoReady(models)) {
      await _waitForModelDownload(provisioner);
      models = await provisioner.provision();
    }

    // 待った後も揃わなければ失敗として公開する（再試行の導線は Step 11）
    if (!_isNemoReady(models)) {
      throw StateError(
        'NeMo モデルが読める状態になっていません'
        '（model: ${models.nemoModel.isValid ? 'OK' : 'NG'}'
        ' / tokens: ${models.nemoTokens.isValid ? 'OK' : 'NG'}）',
      );
    }

    // ④ エンジンを生成する（ここが数秒かかる本体）。
    //    provider が破棄されるときにメモリから解放する（databaseProvider と同じ形）
    //    ※ この生成は同期呼び出しでメインスレッドを止めるため、所要時間を計測する
    //      （spike 指摘C: カクつきの実害判定に使う）
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
  //   fast-follow は Play が自動で始めるので、ここでは fetch せず結果だけを待つ。
  //   「DL中」→ 完了 or 失敗まで待つ／「未開始・失敗で止まっている」→ 即エラー
  //   （エラー時の再取得は Step 11 の再試行が担当）
  // ---------------------------------
  Future<void> _waitForModelDownload(SttModelProvisioner provisioner) async {
    final current = await provisioner.modelDownloadState();

    // DL が進んでいないなら、待たずに失敗として公開する（永久待ちを防ぐ）
    if (current.phase != AssetPackPhase.downloading) {
      throw StateError(
        'NeMo モデルが未配置です（DL状態: ${current.rawStatus ?? current.phase.name}）',
      );
    }

    // DL 中なら、完了か失敗になるまで状態の変化を待つ
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
