import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show min;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:momeo/platform/asset_pack_delivery.dart';
import 'package:momeo/platform/os_transcriber_channel.dart';
import 'package:momeo/stt/stt_audio_worker.dart';
import 'package:momeo/stt/stt_model_provisioner.dart';

// OS の文字起こしが使えない端末（何度やっても結果は同じなので、再試行しない）
class SttUnsupportedError implements Exception {
  const SttUnsupportedError(this.detail);
  final String detail;

  @override
  String toString() => 'SttUnsupportedError: $detail';
}

// ============================================================
// sttEngineProvider — 音声 isolate（SttAudioWorker）をアプリ全体で1つだけ持つ
//
//   OS の文字起こしが使えるかの確かめと音声 isolate の立ち上げを、起動時に1回だけ行い全画面で使い回す。
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
      // 使えない端末では、何度やっても結果は同じなので再試行しない
      if (error is! SttUnsupportedError) _scheduleRetry();
      rethrow;
    }
  }

  // ---------------------------------
  // 起動時の準備処理
  //   ① OS の文字起こしが使えるかを確かめる → ② 音声 isolate の立ち上げ
  // ---------------------------------
  Future<SttAudioWorker> _prepare() async {
    await _ensureOsTranscriberReady();

    final stopwatch = Stopwatch()..start();
    final worker = await SttAudioWorker.spawn();
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

  // ---------------------------------
  // OS の文字起こしがすぐ使えるかを確かめる。使えなければエラーを投げる
  // ---------------------------------
  Future<void> _ensureOsTranscriberReady() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      throw const SttUnsupportedError('iOS・Android 以外では使えません');
    }

    final status = await OsTranscriberChannel.prepare();
    debugPrint(
      '[sttEngine] OS の文字起こし: ${status.state.name}（${status.detail}）',
    );

    switch (status.state) {
      case OsTranscriberState.ready:
        return;
      case OsTranscriberState.unsupported:
        throw SttUnsupportedError(status.detail);
      case OsTranscriberState.downloading:
        throw StateError('言語のモデルをダウンロード中です（${status.detail}）');
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
  // 再試行の本体。準備をやり直す
  // ---------------------------------
  void _retry() {
    ref.invalidateSelf();
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
// sttModelDownloadStateProvider — 認識モデルの自動DL（fast-follow）の進捗
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
