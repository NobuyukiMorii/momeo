import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:record/record.dart';

import 'package:momeo/platform/audio_session_channel.dart';
import 'package:momeo/stt/stt_audio_worker.dart';
import 'package:momeo/stt/stt_downsampler.dart';

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
//   他のアプリが鳴っている間は届いた音を捨てる。iOS ではさらに Bluetooth の
//   マイクを手放してイヤホンを音楽用に戻す（→ 後半の「他のアプリの音に譲る」）。
//
//   所有するのは AudioRecorder だけ。SttAudioWorker は借り物で、
//   dispose では区切り役の解放だけを頼み、認識器には触れない。
// ============================================================

const int _kSampleRate = 16000; // 音声 isolate へ渡すサンプリングレート（VAD・認識モデルの前提）

// iOS は録音のレートが他のアプリの再生音にも効くため 48kHz で録り、16kHz へは自前で落とす
final int _kRecordSampleRate =
    Platform.isIOS ? SttDownsampler.inputSampleRate : _kSampleRate;

// ---------------------------------
// 録音の見張りの設定
// ---------------------------------

const Duration _kWatchdogInterval = Duration(seconds: 2); // 録音の生死を確かめる間隔
const Duration _kAudioStallLimit = Duration(seconds: 5); // これだけ音が届かなければ止まったとみなす
const List<int> _kRestartDelaySeconds = [2, 4, 8, 16, 30]; // 作り直しの失敗が続いたときの待ち時間

// ---------------------------------
// 他のアプリの音に譲る設定
// ---------------------------------

const Duration _kOtherAudioCheckInterval = Duration(milliseconds: 500); // 他のアプリが鳴っているかを確かめる間隔
// 鳴り止んだとみなすまでに、鳴っていない判定が続く回数（一瞬途切れただけで書き留めを再開しない）
const int _kOtherAudioSilentChecksToTakeBack = 4;
// 録音を開いた・Bluetooth のマイクを手放した直後は、経路の組み直しで他のアプリの再生が途切れ、
// 鳴っていないと出ることがある。この間は鳴り止んだと数えない（数えると開き直しで相手の再生を止めてしまう）
const Duration _kOtherAudioSettleTime = Duration(seconds: 3);

// ---------------------------------
// 録音の設定
// ---------------------------------
final RecordConfig _kRecordConfig = _buildRecordConfig(allowsBluetoothMic: true);

// 他のアプリが鳴っている間の設定。Bluetooth のマイクを使わないことで、
// イヤホンが通話用（HFP）に切り替わらず、音楽用（A2DP）のままになる
final RecordConfig _kRecordConfigWhileOtherAudio =
    _buildRecordConfig(allowsBluetoothMic: false);

RecordConfig _buildRecordConfig({required bool allowsBluetoothMic}) {
  return RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: _kRecordSampleRate,
    numChannels: 1,
    // Android は中断を扱わない。扱うと録音がオーディオフォーカスを独占して他のアプリの再生を止め、
    // 他のアプリに奪われると戻ってこない。他のアプリの音は「他のアプリの音に譲る」で捨てる
    audioInterruption: Platform.isIOS
        ? AudioInterruptionMode.pauseResume
        : AudioInterruptionMode.none,
    iosConfig: IosRecordConfig(
      categoryOptions: [
        IosAudioCategoryOption.mixWithOthers,
        IosAudioCategoryOption.defaultToSpeaker,
        if (allowsBluetoothMic) IosAudioCategoryOption.allowBluetooth,
        IosAudioCategoryOption.allowBluetoothA2DP,
      ],
      allowHapticsAndSystemSoundsDuringRecording: true,
    ),
  );
}

class SttListeningPipeline {
  SttListeningPipeline({
    required SttAudioWorker worker,
    required String sileroPath,
    required this.onTranscribed,
    this.onSpeechActiveChanged,
    this.onLevelChanged,
    this.onSpeechDiscarded,
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

  // 区切りの途中の発話を、文字化せずに捨てたときに呼ばれる通知先（任意）。
  // 捨てた発話の文字化結果は届かないので、受け取る側はこれで結果待ちを解く
  final void Function()? onSpeechDiscarded;

  final AudioRecorder _recorder = AudioRecorder();
  // iOS だけ、48kHz で届く音を 16kHz へ落とす係を持つ
  final SttDownsampler? _downsampler = Platform.isIOS ? SttDownsampler() : null;
  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<SttAudioEvent>? _eventSubscription;
  StreamSubscription<RecordState>? _stateSubscription;

  bool _running = false;

  // ---------------------------------
  // 仕事をまたいで読み書きされる状態の印（直すときは、ここに挙げた読み手への影響も確かめる）
  //
  //   _interrupted          立てる: 録音状態の購読（OS の中断で pause）
  //                         下ろす: 録音状態の購読（record）・取り戻す・停止
  //                         読む  : 見張り（作り直さない）、取り戻す（開き直すか）、前面復帰
  //   _restarting           立てる: 作り直し・録音を止めて手放す
  //                         読む  : 見張り・他のアプリの見張り（重ねて走らせない）
  //   _otherAudioPlaying    立てる: 開始（鳴っている中で始めたとき）・鳴り始めた
  //                         下ろす: 取り戻す・停止
  //                         読む  : 音の流し込み（捨てる）、録音を開く（設定を選ぶ）、前面復帰
  //   _bluetoothMicReleased 立てる: 録音を開く（Bluetooth なしの設定のとき）・Bluetooth のマイクを手放す・録音を止めて手放す
  //                         下ろす: 録音を開く（ふつうの設定のとき）・停止
  //                         読む  : 取り戻す（開き直して Bluetooth のマイクに戻すか）
  //   _releasedForOtherAudio 立てる: 録音を止めて手放す
  //                         下ろす: 取り戻す・停止
  //                         読む  : 見張り（作り直さない）
  //   _otherAudioSettlesAt  立てる: 録音を開く・Bluetooth のマイクを手放す（経路が組み直されるため）
  //                         読む  : 他のアプリの見張り・前面復帰（この間は鳴り止んだと数えない）
  // ---------------------------------

  // 見張りが使う状態
  Timer? _watchdog;
  DateTime _lastAudioAt = DateTime.now(); // 最後に音のチャンクが届いた時刻
  bool _interrupted = false; // 中断中（着信など）。この間は止まっていて当たり前
  bool _restarting = false; // 作り直しの最中（多重に走らせない）
  int _restartFailures = 0; // 作り直しに連続で失敗した回数
  DateTime? _restartNotBefore; // 次に作り直しを試してよい時刻

  // 他のアプリの音に譲るための状態
  Timer? _otherAudioTimer;
  bool _otherAudioPlaying = false; // 鳴っている間は届いた音を捨てる
  int _otherAudioSilentChecks = 0; // 鳴っていない判定が続いた回数
  // 今の録音が Bluetooth のマイクを手放している（iOS のみ。取り戻すときに開き直して戻す）
  bool _bluetoothMicReleased = false;
  bool _releasedForOtherAudio = false; // 譲るために録音を止めてイヤホンを手放している
  DateTime? _otherAudioSettlesAt; // この時刻までは、鳴っていない判定を数えない
  bool _checkingOtherAudio = false; // 確かめている最中（多重に走らせない）

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

    // 他のアプリが鳴っているなら、最初から音を捨て、Bluetooth のマイクを使わない設定で開く
    _otherAudioPlaying = await _isOtherAudioPlaying();
    _otherAudioSilentChecks = 0;

    // 録音を開くのはここまで。失敗しても後片付けの要る購読はまだ無い
    final stream = await _openRecordingStream();

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
    // 他のアプリが鳴り始めないか見張り始める
    _startOtherAudioWatch();
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    // 意図した停止なので、見張りを先に下ろす
    _stopWatchdog();
    // 他のアプリの見張りも下ろす
    _stopOtherAudioWatch();
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
    // イヤホンを手放す。録音を閉じただけでは通話用（HFP）につかんだままになり、他のアプリの音がこもる
    await _releaseAudioSessionOnIos();

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
  // イヤホンを手放す（iOS）
  // ---------------------------------
  // 失敗してもログだけ残して止めきる
  Future<void> _releaseAudioSessionOnIos() async {
    if (!Platform.isIOS) return;
    try {
      await AudioSessionChannel.releaseAudioSession();
    } catch (error) {
      debugPrint('[sttPipeline] イヤホンを手放せませんでした: $error');
    }
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
    // 譲ったまま・中断の終わりが届かないまま戻ってきた場合、他のアプリが鳴っていなければ取り戻す
    if ((_otherAudioPlaying || _interrupted) && !_isOtherAudioSettling) {
      if (!await _isOtherAudioPlaying()) {
        await _takeBackFromOtherAudio();
        return;
      }
    }
    // 続けていた場合は、待たずに生死を確かめる
    await _restartIfAudioStalled(ignoresDelay: true);
  }

  // ---------------------------------
  // 録音を開く（開始と作り直しの両方がここを通る）
  // ---------------------------------
  Future<Stream<Uint8List>> _openRecordingStream() {
    // 他のアプリが鳴っている間は Bluetooth のマイクを使わない設定で開くので、
    // 鳴り止んだときに開き直して戻せるよう覚えておく
    _bluetoothMicReleased = Platform.isIOS && _otherAudioPlaying;
    // 開くと経路が組み直されるので、しばらくは鳴り止んだと数えない
    _waitForOtherAudioToSettle();
    return _recorder.startStream(_currentRecordConfig);
  }

  // ---------------------------------
  // 録音の開き直し
  // ---------------------------------
  Future<void> _reopenRecordingStream() async {
    // 録音エンジンごと作り直し、流し込みを繋ぎ直す
    _listenToAudio(await _openRecordingStream());
  }

  // ---------------------------------
  // 音の流し込み
  // ---------------------------------
  void _listenToAudio(Stream<Uint8List> stream) {
    // 見張りの起点を今にする
    _lastAudioAt = DateTime.now();
    // 前の録音の音を持ち越さない
    _downsampler?.reset();
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
    // 他のアプリが鳴っている間は、その音を拾っているので捨てる
    if (_otherAudioPlaying) return;
    // iOS は 48kHz で届くので、16kHz へ落としてから音声 isolate へ渡す
    final downsampler = _downsampler;
    _worker.pushAudio(
      downsampler == null ? pcm16Bytes : downsampler.convert(pcm16Bytes),
    );
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
    // 他のアプリのために手放している間も途絶えていて当たり前（背面では作り直せず、経路の組み直しで相手の音が途切れる）
    if (_releasedForOtherAudio) return;
    // まだ音が届いているなら何もしない
    if (DateTime.now().difference(_lastAudioAt) < _kAudioStallLimit) return;
    // 失敗の直後は待ち時間を置く
    if (!ignoresDelay && !_canRetryRestart()) return;
    // 止まっているので作り直す
    await _restartRecording(reason: '音が途絶えました');
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

  // reason は作り直すきっかけ（ログに残す）
  Future<void> _restartRecording({required String reason}) async {
    // 見張りが重ねて走らないようにする
    _restarting = true;
    debugPrint('[sttPipeline] $reason。録音を作り直します');

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
  // 他のアプリの音に譲る
  //   鳴っている間は届いた音を捨てる。iOS で Bluetooth のマイクを使っていれば手放し、
  //   イヤホンを音楽用に戻す。背面では設定の差し替えも録音の開き直しも iOS に
  //   拒否されるため、そのときは録音を止めてイヤホンごと手放し、前面で再開する
  // ---------------------------------

  // 他のアプリが鳴っている間は、Bluetooth のマイクを使わない設定で開く
  RecordConfig get _currentRecordConfig =>
      _otherAudioPlaying ? _kRecordConfigWhileOtherAudio : _kRecordConfig;

  // 確かめられないときは鳴っていない扱いにする（録音は止めない）
  Future<bool> _isOtherAudioPlaying() async {
    try {
      return await AudioSessionChannel.isOtherAudioPlaying();
    } catch (error) {
      debugPrint('[sttPipeline] 他のアプリの音を確かめられませんでした: $error');
      return false;
    }
  }

  void _startOtherAudioWatch() {
    // 二重に走らせない
    _otherAudioTimer?.cancel();
    // 一定間隔で、他のアプリが鳴っているかを確かめる
    _otherAudioTimer = Timer.periodic(
      _kOtherAudioCheckInterval,
      (_) => _checkOtherAudio(),
    );
  }

  // 経路の組み直しの直後か（この間は鳴っていない判定を数えない）
  bool get _isOtherAudioSettling {
    final settlesAt = _otherAudioSettlesAt;
    return settlesAt != null && DateTime.now().isBefore(settlesAt);
  }

  void _waitForOtherAudioToSettle() {
    _otherAudioSettlesAt = DateTime.now().add(_kOtherAudioSettleTime);
  }

  void _stopOtherAudioWatch() {
    _otherAudioTimer?.cancel();
    _otherAudioTimer = null;
    // 次に始めるときへ持ち越さない
    _otherAudioPlaying = false;
    _otherAudioSilentChecks = 0;
    _bluetoothMicReleased = false;
    _releasedForOtherAudio = false;
  }

  Future<void> _checkOtherAudio() async {
    // 止まっている・作り直しの最中・確かめている最中なら何もしない
    if (!_running || _restarting || _checkingOtherAudio) return;
    _checkingOtherAudio = true;
    try {
      final isPlaying = await AudioSessionChannel.isOtherAudioPlaying();
      if (isPlaying) {
        _otherAudioSilentChecks = 0;
        if (!_otherAudioPlaying) await _yieldToOtherAudio();
      } else if (_otherAudioPlaying) {
        // 経路の組み直しの直後は、一瞬途切れているだけかもしれないので数えない
        if (_isOtherAudioSettling) {
          _otherAudioSilentChecks = 0;
          return;
        }
        // 鳴っていない判定がしばらく続いてから取り戻す
        _otherAudioSilentChecks++;
        if (_otherAudioSilentChecks >= _kOtherAudioSilentChecksToTakeBack) {
          await _takeBackFromOtherAudio();
        }
      }
    } catch (error) {
      debugPrint('[sttPipeline] 他のアプリの音を確かめられませんでした: $error');
    } finally {
      _checkingOtherAudio = false;
    }
  }

  // ---------------------------------
  // 他のアプリが鳴り始めたとき
  // ---------------------------------
  Future<void> _yieldToOtherAudio() async {
    // 先に捨て始める（ここから届く音は音声 isolate へ渡さない）
    _otherAudioPlaying = true;
    // 途中まで拾っていた発話は他のアプリの音が混ざっているので、文字化せずに捨てる
    await _worker.startListening(sileroPath: _sileroPath);
    onSpeechDiscarded?.call();

    // Android と iOS の本体マイクは捨てるだけでよい。設定を替えなければ背面でも録音が続き、
    // 鳴り止めばそのまま再開できる
    if (!Platform.isIOS || !await AudioSessionChannel.isBluetoothMicInUse()) return;

    try {
      // 録音を止めずに Bluetooth のマイクを手放し、イヤホンを音楽用に戻す（前面でだけ通る）
      await AudioSessionChannel.releaseBluetoothMic();
      _bluetoothMicReleased = true;
      // 手放すと経路が組み直されるので、しばらくは鳴り止んだと数えない
      _waitForOtherAudioToSettle();
    } catch (error) {
      // 背面で拒否されたときは、録音を止めてイヤホンごと手放す（再開は前面に戻ったとき）
      await _releaseRecordingForOtherAudio();
    }
  }

  // ---------------------------------
  // 他のアプリが鳴り止んだとき
  // ---------------------------------
  Future<void> _takeBackFromOtherAudio() async {
    // Bluetooth のマイクを手放している・録音を止めている・中断されたままなら、開き直しが要る
    // （中断の終わりを知らせないアプリもあるので、知らせを待たずに自分で再開する）
    final needsReopen = _bluetoothMicReleased || _interrupted;
    _otherAudioPlaying = false;
    _otherAudioSilentChecks = 0;
    _releasedForOtherAudio = false;
    _interrupted = false;
    if (!needsReopen) return;

    // 設定の差し替えだけだと録音エンジンが黙って止まるため、待たずにその場で開き直す。
    // 開き直しで Bluetooth のマイクを使える設定に戻る（_bluetoothMicReleased も下りる）。
    // 背面で失敗しても、見張りが作り直しを続け、前面に戻れば再開できる
    await _restartRecording(reason: '他のアプリが鳴り止みました');
  }

  // ---------------------------------
  // 録音を止めてイヤホンごと手放す（見張りの作り直しとは重ねない）
  // ---------------------------------
  Future<void> _releaseRecordingForOtherAudio() async {
    _restarting = true;
    try {
      // 録音からの流し込みを切る
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      try {
        // 録音を閉じる
        await _recorder.stop();
      } catch (_) {
        // 既に止まっている場合の例外は無視して手放しへ進む
      }
      // 取り戻すまで、見張りに作り直しをさせない
      _bluetoothMicReleased = true;
      _releasedForOtherAudio = true;
      await AudioSessionChannel.releaseAudioSession();
    } catch (error) {
      debugPrint('[sttPipeline] イヤホンを手放せませんでした: $error');
    } finally {
      _restarting = false;
    }
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
