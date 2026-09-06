import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:momeo/platform/asset_pack_delivery.dart';
import 'package:momeo/stt/stt_audio_worker.dart';
import 'package:momeo/stt/stt_model_provisioner.dart';

// ============================================================
// sttEngineProvider — 音声 isolate（SttAudioWorker）をアプリ全体で1つだけ持つ
//
//   認識器の読み込みは数秒かかるため、起動時に1回だけ行い全画面で使い回す。
//   状態は AsyncValue で公開する（loading=準備中 / data=完了 / error=失敗）。
//
//   準備が失敗したら、この provider が自分でバックオフ付きの再試行を予約する。
//   画面側（ゲート・待ち画面）は状態を表示するだけで、復帰には関与しない。
// ============================================================

final sttEngineProvider =
    AsyncNotifierProvider<SttEngineNotifier, SttAudioWorker>(
  SttEngineNotifier.new,
  // Riverpod 標準の自動リトライ（0.2〜6.4秒）を無効化。自前のバックオフと二重に走るため
  retry: (retryCount, error) => null,
);

class SttEngineNotifier extends AsyncNotifier<SttAudioWorker> {
  // ---------------------------------
  // 自動再試行の設定（間隔は失敗のたびに1段広げ、最後の値が上限）
  // ---------------------------------
  static const _retryDelaySeconds = [2, 4, 8, 16, 30];
  static const _restartSuggestionThreshold = 5;

  int _consecutiveFailures = 0;
  Timer? _retryTimer;

  // ---------------------------------
  // エンジンの準備を実行する。失敗したら自動で再試行を予約する
  // ---------------------------------
  @override
  Future<SttAudioWorker> build() async {
    // 再実行の入口。予約済みの再試行が残っていれば止める（多重予約を防ぐ）
    _retryTimer?.cancel();
    ref.onDispose(() => _retryTimer?.cancel());

    try {
      final worker = await _prepare();
      _consecutiveFailures = 0;
      ref.read(sttRestartSuggestedProvider.notifier).set(false);
      return worker;
    } catch (error) {
      _scheduleRetry();
      rethrow;
    }
  }

  // ---------------------------------
  // 起動時の準備処理
  //   ① モデルパス取得 → ② (Android初回のみ) DL完了待ち → ③ 音声 isolate の立ち上げ
  // ---------------------------------
  Future<SttAudioWorker> _prepare() async {
    final provisioner = SttModelProvisioner();

    // ① モデル3ファイルのパス・整合性を取得（silero の端末コピーもこの中で済む）
    var models = await provisioner.provision();

    // ② NeMo が未到着なら、DL中に限り完了を待ってからパスを取り直す
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

    // ③ 音声 isolate を立ち上げる。認識器の生成（数秒）もこの中で済む
    final stopwatch = Stopwatch()..start();
    final worker = await SttAudioWorker.spawn(
      modelPath: models.nemoModel.path,
      tokensPath: models.nemoTokens.path,
    );
    stopwatch.stop();
    ref.onDispose(worker.dispose);

    if (kDebugMode) {
      debugPrint(
        '[sttEngine] エンジンの読み込みが完了しました'
        '（${stopwatch.elapsedMilliseconds}ms・音声 isolate 内）',
      );
    }
    return worker;
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

  // ---------------------------------
  // 次の再試行をバックオフ付きで予約する
  // ---------------------------------
  void _scheduleRetry() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= _restartSuggestionThreshold) {
      ref.read(sttRestartSuggestedProvider.notifier).set(true);
    }

    final delayIndex =
        min(_consecutiveFailures - 1, _retryDelaySeconds.length - 1);
    _retryTimer = Timer(
      Duration(seconds: _retryDelaySeconds[delayIndex]),
      _retry,
    );

    if (kDebugMode) {
      debugPrint(
        '[sttEngine] 準備に失敗しました（連続 $_consecutiveFailures 回目）。'
        '${_retryDelaySeconds[delayIndex]}秒後に自動で再試行します',
      );
    }
  }

  // ---------------------------------
  // 再試行の本体。DL起因の失敗なら再取得を頼んでから準備をやり直す
  // ---------------------------------
  Future<void> _retry() async {
    try {
      final provisioner = SttModelProvisioner();
      final download = await provisioner.modelDownloadState();
      if (download.phase == AssetPackPhase.notStarted ||
          download.phase == AssetPackPhase.failed) {
        await provisioner.requestModelDownload();
        await _waitForDownloadingTransition(provisioner);
      }
    } catch (_) {
      // 再取得の依頼に失敗しても準備のやり直しには進む
      // （また失敗すれば次のバックオフに乗る）
    }
    ref.invalidateSelf();
  }

  // fetch 直後はDL状態の反映にラグがあるため、DLが始まるまで少しだけ待つ
  Future<void> _waitForDownloadingTransition(
    SttModelProvisioner provisioner,
  ) async {
    try {
      await provisioner
          .watchModelDownload()
          .firstWhere(
            (state) =>
                state.phase != AssetPackPhase.notStarted &&
                state.phase != AssetPackPhase.failed,
          )
          .timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // 遷移が観測できなくても再試行は続ける
    }
  }
}

// ============================================================
// sttRestartSuggestedProvider — 待ち画面を「アプリを再起動してください」に切り替えるべきか
// ============================================================
final sttRestartSuggestedProvider =
    NotifierProvider<SttRestartSuggestionNotifier, bool>(
  SttRestartSuggestionNotifier.new,
);

class SttRestartSuggestionNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  // SttEngineNotifier が成否に応じて呼ぶ（画面側は watch するだけ）
  void set(bool suggested) => state = suggested;
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
