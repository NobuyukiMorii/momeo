import 'dart:async';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:record/record.dart';

import 'package:momeo/stt/stt_audio_worker.dart';

// ============================================================
// リスニングの録音パイプライン（録音 → 音声 isolate → 通知）
//
//   マイクの音を連続キャプチャして音声 isolate へ流し、そこから戻ってくる
//   「発話中フラグ・音量・確定テキスト」をコールバックへ配る。
//   区切りと文字化は音声 isolate の担当で、ここでは一切行わない。
//
//   録音は黙って止まることがあるため、音のチャンクが届き続けているかを
//   見張り、途絶えたら録音を作り直す（→ 後半の「録音の見張り」）。
//
//   所有するのは AudioRecorder だけ。SttAudioWorker は借り物で、
//   dispose では区切り役の解放だけを頼み、認識器には触れない。
// ============================================================

const int _kSampleRate = 16000; // 録音のサンプリングレート（VAD・NeMo の前提）

// ---------------------------------
// 録音の見張りの設定
// ---------------------------------

const Duration _kWatchdogInterval = Duration(seconds: 2); // 録音の生死を確かめる間隔
const Duration _kAudioStallLimit = Duration(seconds: 5); // これだけ音が届かなければ止まったとみなす
const List<int> _kRestartDelaySeconds = [2, 4, 8, 16, 30]; // 作り直しの失敗が続いたときの待ち時間

// ---------------------------------
// 録音の設定
// ---------------------------------
const RecordConfig _kRecordConfig = RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: _kSampleRate,
  numChannels: 1,
  audioInterruption: AudioInterruptionMode.pauseResume,
  iosConfig: IosRecordConfig(
    categoryOptions: [
      IosAudioCategoryOption.mixWithOthers,
      IosAudioCategoryOption.defaultToSpeaker,
      IosAudioCategoryOption.allowBluetooth,
      IosAudioCategoryOption.allowBluetoothA2DP,
    ],
    allowHapticsAndSystemSoundsDuringRecording: true,
  ),
);

class SttListeningPipeline {
  SttListeningPipeline({
    required SttAudioWorker worker,
    required String sileroPath,
    required this.onTranscribed,
    this.onSpeechActiveChanged,
    this.onLevelChanged,
  })  : _worker = worker,
        _sileroPath = sileroPath;

  final SttAudioWorker _worker;
  final String _sileroPath;

  // 1発話ぶんの文字化が終わるたびに呼ばれる通知先
  final void Function(SttTranscribed result) onTranscribed;

  // 発話中かどうかが切り替わるたびに呼ばれる通知先（任意）
  final void Function(bool isActive)? onSpeechActiveChanged;

  // マイク音量メーター用に、チャンクごとのピーク音量を渡す通知先（任意）
  final void Function(double level)? onLevelChanged;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<SttAudioEvent>? _eventSubscription;
  StreamSubscription<RecordState>? _stateSubscription;

  bool _running = false;

  // 見張りが使う状態
  Timer? _watchdog;
  DateTime _lastAudioAt = DateTime.now(); // 最後に音のチャンクが届いた時刻
  bool _interrupted = false; // 中断中（着信など）。この間は止まっていて当たり前
  bool _restarting = false; // 作り直しの最中（多重に走らせない）
  int _restartFailures = 0; // 作り直しに連続で失敗した回数
  DateTime? _restartNotBefore; // 次に作り直しを試してよい時刻

  // ---------------------------------
  // リスニングの開始 / 停止
  // ---------------------------------

  Future<void> start() async {
    if (_running) return;

    // 権限フローで許可済みの前提だが、念のため確認する
    final granted = await _recorder.hasPermission();
    if (!granted) {
      throw StateError('マイクの利用が許可されていません（RECORD_AUDIO）');
    }

    await _worker.startListening(sileroPath: _sileroPath);

    // 録音を開くのはここまで。失敗しても後片付けの要る購読はまだ無い
    final stream = await _recorder.startStream(_kRecordConfig);

    // 通知の購読を先に始めてから音声を流す（順番が逆だと最初の通知を取りこぼす）
    _eventSubscription = _worker.events.listen(
      _onWorkerEvent,
      onError: (Object error) => debugPrint('[sttPipeline] 音声 isolate のエラー: $error'),
    );
    // 中断中かどうかを見分けられるようにする
    _observeRecorderState();
    // 届いた音を音声 isolate へ流し始める
    _listenToAudio(stream);
    // ここから先はリスニング中として扱う
    _running = true;
    // 音が途絶えていないか見張り始める
    _startWatchdog();
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    // 意図した停止なので、見張りを先に下ろす
    _stopWatchdog();
    // 録音状態の購読を切る
    await _stateSubscription?.cancel();
    // 次の start で貼り直せるようにする
    _stateSubscription = null;
    // 中断中かどうかの記憶を持ち越さない
    _interrupted = false;
    // 作り直しの失敗回数を持ち越さない
    _restartFailures = 0;
    // 次は待たずに作り直せる状態に戻す
    _restartNotBefore = null;
    // 音の流し込みを止める
    await _audioSubscription?.cancel();
    // 次の start で繋ぎ直せるようにする
    _audioSubscription = null;
    try {
      // 録音を閉じる
      await _recorder.stop();
    } catch (_) {
      // 停止時の例外は致命的でないため無視
    }

    // 末尾に残った発話を押し出す。確定テキストは通知で戻ってくるため、
    // それを受け取り終えてから購読を切る
    try {
      await _worker.stopListening();
    } catch (error) {
      debugPrint('[sttPipeline] 末尾の発話を確定できませんでした: $error');
    }
    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  // ---------------------------------
  // フォアグラウンド復帰時の立て直し
  // ---------------------------------
  Future<void> ensureRunning() async {
    // 止めていた場合
    if (!_running) {
      // ふつうに始め直す
      await start();
      // 生死の確認は要らない
      return;
    }
    // 続けていた場合は、待たずに生死を確かめる
    await _restartIfAudioStalled(ignoresDelay: true);
  }

  // ---------------------------------
  // 録音ストリームの受け取り
  // ---------------------------------

  // ---------------------------------
  // 録音の開き直し
  // ---------------------------------
  Future<void> _reopenRecordingStream() async {
    // 録音エンジンごと作り直し、流し込みを繋ぎ直す
    _listenToAudio(await _recorder.startStream(_kRecordConfig));
  }

  // ---------------------------------
  // 音の流し込み
  // ---------------------------------
  void _listenToAudio(Stream<Uint8List> stream) {
    // 見張りの起点を今にする
    _lastAudioAt = DateTime.now();
    // 届いたチャンクを音声 isolate へ渡す
    _audioSubscription = stream.listen(
      // 1チャンクぶんの受け取り
      _onAudioChunk,
      // エラーはログだけ。立て直しは見張りに任せる
      onError: (Object error) => debugPrint('[sttPipeline] 録音ストリームのエラー: $error'),
    );
  }

  // ---------------------------------
  // 音のチャンクが届いたとき
  // ---------------------------------
  void _onAudioChunk(Uint8List pcm16Bytes) {
    // 届いた時刻を残す（見張りが見る）
    _lastAudioAt = DateTime.now();
    // 音声 isolate へ渡す
    _worker.pushAudio(pcm16Bytes);
  }

  // ---------------------------------
  // 中断中かどうかの把握
  // ---------------------------------
  void _observeRecorderState() {
    // 中断されると pause が届く
    _stateSubscription = _recorder.onStateChanged().listen(
      (state) => _interrupted = state == RecordState.pause,
      onError: (Object error) => debugPrint('[sttPipeline] 録音状態のエラー: $error'),
    );
  }

  // ---------------------------------
  // 録音の見張り
  // ---------------------------------

  void _startWatchdog() {
    // 二重に走らせない
    _watchdog?.cancel();
    // 一定間隔で録音の生死を確かめる
    _watchdog = Timer.periodic(
      // 確かめる間隔
      _kWatchdogInterval,
      // 途絶えていれば作り直す
      (_) => _restartIfAudioStalled(),
    );
  }

  // ---------------------------------
  // 見張りの停止
  // ---------------------------------
  void _stopWatchdog() {
    // 予約を取り消す
    _watchdog?.cancel();
    // 次に始めるときへ備える
    _watchdog = null;
  }

  // ---------------------------------
  // 音が途絶えていれば録音を作り直す
  // ---------------------------------
  Future<void> _restartIfAudioStalled({bool ignoresDelay = false}) async {
    // 止まっている・作り直しの最中なら何もしない
    if (!_running || _restarting) return;
    // 中断中は途絶えていて当たり前
    if (_interrupted) return;
    // まだ音が届いているなら何もしない
    if (DateTime.now().difference(_lastAudioAt) < _kAudioStallLimit) return;
    // 失敗の直後は待ち時間を置く
    if (!ignoresDelay && !_canRetryRestart()) return;
    // 止まっているので作り直す
    await _restartRecording();
  }

  // ---------------------------------
  // 作り直しを試してよい時刻か
  // ---------------------------------
  bool _canRetryRestart() {
    // 次に試してよい時刻（無ければ予約なし）
    final notBefore = _restartNotBefore;
    // 予約が無いか、その時刻を過ぎていれば試してよい
    return notBefore == null || !DateTime.now().isBefore(notBefore);
  }

  Future<void> _restartRecording() async {
    // 見張りが重ねて走らないようにする
    _restarting = true;
    debugPrint('[sttPipeline] 音が途絶えました。録音を作り直します');

    // 失敗しても待ち時間を置いて次に繋ぐ
    try {
      // ここで失敗しても作り直しは続ける
      try {
        // 途中まで拾っていた発話を確定させる
        await _worker.stopListening();
      } catch (error) {
        debugPrint('[sttPipeline] 作り直し前の発話を確定できませんでした: $error');
      }

      // 古い録音からの流し込みを切る
      await _audioSubscription?.cancel();
      // 繋ぎ直せるように手放す
      _audioSubscription = null;
      try {
        // 古い録音を閉じる
        await _recorder.stop();
      } catch (_) {
        // 既に止まっている場合の例外は無視して開き直しへ進む
      }

      // 作り直しの最中にリスニングが終わっていたら開き直さない
      if (!_running) return;

      // 区切り役を用意し直す
      await _worker.startListening(sileroPath: _sileroPath);
      // 新しい入力デバイスで録音を開き直す
      await _reopenRecordingStream();

      // 成功したので失敗回数を戻す
      _restartFailures = 0;
      // 待ち時間の予約も消す
      _restartNotBefore = null;
      // 復帰したことを残す
      debugPrint('[sttPipeline] 録音を作り直しました');
    } catch (error) {
      _delayNextRestart();
      debugPrint('[sttPipeline] 録音を作り直せませんでした: $error');
    } finally {
      _restarting = false;
    }
  }

  // ---------------------------------
  // 次に作り直しを試すまでの待ち時間を決める
  // ---------------------------------
  void _delayNextRestart() {
    // 失敗を1つ数える
    _restartFailures++;
    // 失敗のたびに1段広げ、最後の値で頭打ちにする
    final delayIndex =
        min(_restartFailures - 1, _kRestartDelaySeconds.length - 1);
    // 次に試してよい時刻を決める
    _restartNotBefore = DateTime.now().add(
      // 段に応じた待ち時間
      Duration(seconds: _kRestartDelaySeconds[delayIndex]),
    );
  }

  // ---------------------------------
  // 音声 isolate からの通知を配る
  // ---------------------------------

  void _onWorkerEvent(SttAudioEvent event) {
    switch (event) {
      case SttSpeechActiveChanged(:final isActive):
        onSpeechActiveChanged?.call(isActive);
      case SttMicLevelMeasured(:final level):
        onLevelChanged?.call(level);
      case SttTranscribed():
        if (kDebugMode) {
          debugPrint(
            '[sttPipeline] 発話 ${event.durationSec.toStringAsFixed(1)}s'
            ' → 転写 ${event.elapsedMs}ms'
            ' → 「${event.text}」',
          );
        }
        onTranscribed(event);
    }
  }

  // ---------------------------------
  // 後始末（借り物の認識器には触らない）
  // ---------------------------------

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
    try {
      await _worker.releaseListening();
    } catch (_) {
      // isolate が既に終わっている場合は解放するものが無い
    }
  }
}
