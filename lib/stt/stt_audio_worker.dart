import 'dart:async';
import 'dart:collection' show ListQueue;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

// ============================================================
// 音声処理（VAD の区切り・認識モデルの文字化）を専用 isolate に閉じ込める窓口
//
//   認識器も VAD もこの isolate の中だけに存在するため、UI 側から
//   触れるのは Future を返すメソッドと通知イベントだけになる。
//   数秒かかる処理で UI スレッドが止まることは構造上起きない。
// ============================================================

const int _kSampleRate = 16000; // 1秒あたりのサンプル数
const int _kBytesPerSample = 2; // PCM16 = 1サンプル2バイト
const int _kInt16Amplitude = 32768; // PCM16 の正規化基準（2^15）
const int _kVadWindow = 512; // VAD に1回で渡すサンプル数（16kHz の Silero 用）
const double _kVadBufferSeconds = 60; // VAD 内部バッファ（秒）。maxSpeechDuration を余裕で収める

const double _kMinSilenceDuration = 3.0;
// 「.」を早く出すため短めにする。判定前に話した分は _SpeechHeadKeeper が区切りの頭へ補う
const double _kMinSpeechDuration = 0.5;
const double _kMaxSpeechDuration = 30.0;

// どれくらいの音を「声」とみなすか。既定の 0.5 では語頭を取りこぼす
const double _kVadThreshold = 0.35;

// 発話と判定される前の声を、区切りの頭へ補うときにさかのぼれる上限（区切りの開始から何秒前まで）
const int _kHeadLookbackSeconds = 10;

// 音を覚えておく長さ（秒）。区切りを文字化するのは最長の発話と3秒の無音の後なので、そのぶんも足す
const int _kHeadHistorySeconds =
    _kHeadLookbackSeconds + _kMaxSpeechDuration ~/ 1 + _kMinSilenceDuration ~/ 1 + 1;

// 認識する言語。空文字は自動判定。日本語に固定すると普通話が崩れ、日本語側の利得も無い
const String _kRecognitionLanguage = '';

// ============================================================
// 音声 isolate から届く通知
// ============================================================

sealed class SttAudioEvent {
  const SttAudioEvent();
}

// 発話中かどうかが切り替わった（true: 発話の開始 / false: 発話の終了）
class SttSpeechActiveChanged extends SttAudioEvent {
  const SttSpeechActiveChanged(this.isActive);
  final bool isActive;
}

// 音量メーター用のピーク音量（0.0=無音 〜 1.0=最大）
class SttMicLevelMeasured extends SttAudioEvent {
  const SttMicLevelMeasured(this.level);
  final double level;
}

// 1発話ぶんの文字化が終わった（text は空になることもある）
class SttTranscribed extends SttAudioEvent {
  const SttTranscribed({
    required this.text,
    required this.durationSec,
    required this.elapsedMs,
  });

  final String text;
  final double durationSec; // 発話の長さ（秒）
  final int elapsedMs; // 文字化にかかった時間（ミリ秒）
}

// ============================================================
// SttAudioWorker — UI 側が持つ音声 isolate の連絡口
// ============================================================

class SttAudioWorker {
  SttAudioWorker._(this._isolate, this._fromWorker);

  // 認識器の生成まで済ませた isolate を立ち上げる（数秒かかるが UI は止まらない）
  static Future<SttAudioWorker> spawn({
    required String modelPath,
    required String tokensPath,
  }) async {
    final fromWorker = ReceivePort();
    final isolate = await Isolate.spawn(
      _runAudioIsolate,
      _WorkerStartup(
        toMain: fromWorker.sendPort,
        modelPath: modelPath,
        tokensPath: tokensPath,
      ),
      onError: fromWorker.sendPort,
      onExit: fromWorker.sendPort,
      debugName: 'stt-audio',
    );

    final worker = SttAudioWorker._(isolate, fromWorker);
    fromWorker.listen(worker._receive);
    try {
      await worker._ready.future;
    } catch (_) {
      worker._shutdownNow();
      rethrow;
    }
    return worker;
  }

  final Isolate _isolate;
  final ReceivePort _fromWorker;

  final Completer<void> _ready = Completer<void>();
  final Map<int, Completer<void>> _pending = <int, Completer<void>>{};
  final StreamController<SttAudioEvent> _events =
      StreamController<SttAudioEvent>.broadcast();

  SendPort? _toWorker;
  int _nextCommandId = 0;
  bool _closed = false;

  // 発話中フラグ・音量・確定テキストがここに流れてくる
  Stream<SttAudioEvent> get events => _events.stream;

  // ---------------------------------
  // 音声 isolate への依頼
  // ---------------------------------

  // 区切り役（VAD）を用意して、音声を受け付けられる状態にする
  Future<void> startListening({required String sileroPath}) {
    return _request(
      _StartListeningCommand(id: _nextCommandId++, sileroPath: sileroPath),
    );
  }

  // 録音チャンクを送る。返事は待たず、結果は通知で戻ってくる
  void pushAudio(Uint8List pcm16Bytes) {
    _toWorker?.send(_PushAudioCommand(pcm16Bytes));
  }

  // 末尾に残った発話を押し出す。文字化まで終わってから返る
  Future<void> stopListening() {
    return _request(_StopListeningCommand(id: _nextCommandId++));
  }

  // 区切り役を解放する（認識器は残す）
  Future<void> releaseListening() {
    return _request(_ReleaseListeningCommand(id: _nextCommandId++));
  }

  // 認識器ごと片付けて isolate を終わらせる
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _toWorker?.send(const _ShutdownCommand());
    await _events.close();
  }

  // ---------------------------------
  // やり取りの土台
  // ---------------------------------

  Future<void> _request(_Command command) {
    final toWorker = _toWorker;
    if (toWorker == null || _closed) {
      return Future.error(StateError('音声 isolate は使える状態ではありません'));
    }
    final completer = Completer<void>();
    _pending[command.id] = completer;
    toWorker.send(command);
    return completer.future;
  }

  void _receive(Object? message) {
    // isolate が終了すると onExit から null が届く
    if (message == null) {
      _fromWorker.close();
      _failAll('音声 isolate が終了しました');
      return;
    }

    // isolate 内の未捕捉エラーは onError から [エラー, スタックトレース] で届く
    if (message is List) {
      _failAll('音声 isolate でエラーが起きました: ${message.first}');
      return;
    }

    if (message is _WorkerReady) {
      _toWorker = message.toWorker;
      _ready.complete();
      return;
    }

    if (message is _WorkerFailed) {
      _ready.completeError(StateError(message.reason));
      return;
    }

    if (message is _Reply) {
      final completer = _pending.remove(message.id);
      final error = message.error;
      if (error == null) {
        completer?.complete();
      } else {
        completer?.completeError(StateError(error));
      }
      return;
    }

    if (message is SttAudioEvent) {
      _events.add(message);
    }
  }

  // isolate が落ちたら、待っている依頼をまとめて失敗させる
  void _failAll(String reason) {
    if (_closed) return;
    _closed = true;

    final error = StateError(reason);
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
    if (_events.hasListener) _events.addError(error);
    _events.close();
  }

  // 立ち上げに失敗したときの後始末
  void _shutdownNow() {
    _closed = true;
    _fromWorker.close();
    _events.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

// ============================================================
// 表 ↔ 裏でやり取りするメッセージ
// ============================================================

class _WorkerStartup {
  const _WorkerStartup({
    required this.toMain,
    required this.modelPath,
    required this.tokensPath,
  });

  final SendPort toMain;
  final String modelPath;
  final String tokensPath;
}

// 認識器の生成まで済んだ合図。以後はこの窓口に依頼を送る
class _WorkerReady {
  const _WorkerReady(this.toWorker);
  final SendPort toWorker;
}

// 認識器の生成に失敗した合図
class _WorkerFailed {
  const _WorkerFailed(this.reason);
  final String reason;
}

// 返事を待つ依頼の共通部分（id で依頼と返事を結ぶ）
sealed class _Command {
  const _Command(this.id);
  final int id;
}

class _StartListeningCommand extends _Command {
  const _StartListeningCommand({required int id, required this.sileroPath})
      : super(id);
  final String sileroPath;
}

class _StopListeningCommand extends _Command {
  const _StopListeningCommand({required int id}) : super(id);
}

class _ReleaseListeningCommand extends _Command {
  const _ReleaseListeningCommand({required int id}) : super(id);
}

// 返事の要らない依頼
class _PushAudioCommand {
  const _PushAudioCommand(this.bytes);
  final Uint8List bytes;
}

class _ShutdownCommand {
  const _ShutdownCommand();
}

class _Reply {
  const _Reply({required this.id, this.error});
  final int id;
  final String? error;
}

// ============================================================
// ここから下は音声 isolate の中でだけ動く
// ============================================================

void _runAudioIsolate(_WorkerStartup startup) {
  final toMain = startup.toMain;
  final commands = ReceivePort();

  final _AudioEngine engine;
  try {
    sherpa.initBindings();
    engine = _AudioEngine(
      modelPath: startup.modelPath,
      tokensPath: startup.tokensPath,
      onEvent: toMain.send,
    );
  } catch (error) {
    toMain.send(_WorkerFailed('$error'));
    commands.close();
    return;
  }

  toMain.send(_WorkerReady(commands.sendPort));

  commands.listen((Object? message) {
    if (message is _PushAudioCommand) {
      engine.acceptAudio(message.bytes);
      return;
    }

    if (message is _ShutdownCommand) {
      engine.dispose();
      commands.close();
      return;
    }

    if (message is! _Command) return;

    try {
      if (message is _StartListeningCommand) {
        engine.startListening(message.sileroPath);
      } else if (message is _StopListeningCommand) {
        engine.stopListening();
      } else if (message is _ReleaseListeningCommand) {
        engine.releaseListening();
      }
      toMain.send(_Reply(id: message.id));
    } catch (error) {
      toMain.send(_Reply(id: message.id, error: '$error'));
    }
  });
}

// ---------------------------------
// 音声 isolate が持つ道具一式（認識器・VAD・変換バッファ）
// ---------------------------------
class _AudioEngine {
  _AudioEngine({
    required String modelPath,
    required String tokensPath,
    required this.onEvent,
  }) : _recognizer = _createRecognizer(
          modelPath: modelPath,
          tokensPath: tokensPath,
        );

  final void Function(SttAudioEvent event) onEvent;
  final sherpa.OfflineRecognizer _recognizer;

  sherpa.VoiceActivityDetector? _vad;
  String? _sileroPath;

  // VAD へ窓単位で渡すための累積バッファ
  final List<double> _floatBuffer = <double>[];

  bool _speechActive = false;

  // 発話と判定される前の声を、区切りの頭へ補う係
  final _SpeechHeadKeeper _headKeeper = _SpeechHeadKeeper();

  // SenseVoice の枠にモデル本体のパスを入れることで読み方が決まる
  static sherpa.OfflineRecognizer _createRecognizer({
    required String modelPath,
    required String tokensPath,
  }) {
    final config = sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        senseVoice: sherpa.OfflineSenseVoiceModelConfig(
          model: modelPath,
          language: _kRecognitionLanguage,
          useInverseTextNormalization: true, // 数字や句読点を読みやすい形にする
        ),
        tokens: tokensPath,
        numThreads: 1,
        debug: kDebugMode,
      ),
    );
    return sherpa.OfflineRecognizer(config);
  }

  static sherpa.VoiceActivityDetector _createVad(String sileroPath) {
    return sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: sileroPath,
          threshold: _kVadThreshold,
          minSilenceDuration: _kMinSilenceDuration,
          minSpeechDuration: _kMinSpeechDuration,
          maxSpeechDuration: _kMaxSpeechDuration,
        ),
        sampleRate: _kSampleRate,
        numThreads: 1,
      ),
      bufferSizeInSeconds: _kVadBufferSeconds,
    );
  }

  // ---------------------------------
  // 受け付けの開始・終了
  // ---------------------------------

  void startListening(String sileroPath) {
    // 同じモデルなら作り直さず、中身を空にして使い回す
    if (_vad != null && sileroPath == _sileroPath) {
      _vad!.clear();
      // 録音の切れ目より前の音は補わない
      _headKeeper.markBoundary();
    } else {
      _vad?.free();
      _vad = _createVad(sileroPath);
      _sileroPath = sileroPath;
      // VAD を作り直すと位置が0から数え直しになるため、補う係も作り直す
      _headKeeper.start(sileroPath);
    }
    _floatBuffer.clear();
    _speechActive = false;
  }

  void stopListening() {
    final vad = _vad;
    if (vad == null) return;

    _notifySpeechActive(detected: false);
    vad.flush();
    _drainAndTranscribe(vad);
  }

  void releaseListening() {
    _vad?.free();
    _vad = null;
    _headKeeper.release();
    _sileroPath = null;
    _floatBuffer.clear();
    _speechActive = false;
  }

  void dispose() {
    releaseListening();
    _recognizer.free();
  }

  // ---------------------------------
  // 音声チャンクの受信
  //   ① Float32 へ変換 → ② 512サンプル窓で VAD に供給 → ③ 区切り → 文字化
  // ---------------------------------

  void acceptAudio(Uint8List bytes) {
    final vad = _vad;
    if (vad == null) return;

    final samples = _pcm16ToFloat32(bytes);
    _floatBuffer.addAll(samples);

    while (_floatBuffer.length >= _kVadWindow) {
      final window = Float32List.fromList(_floatBuffer.sublist(0, _kVadWindow));
      _floatBuffer.removeRange(0, _kVadWindow);
      vad.acceptWaveform(window);
      // 本番の VAD と同じ窓を、補う係にも渡す（声らしかったかを覚えておく）
      _headKeeper.acceptWindow(window);
    }

    // 発話中かどうかの変化は、確定テキストより先に知らせる
    _notifySpeechActive(detected: vad.isDetected());
    _drainAndTranscribe(vad);
    onEvent(SttMicLevelMeasured(_peakLevel(samples)));
  }

  void _notifySpeechActive({required bool detected}) {
    if (detected == _speechActive) return;
    _speechActive = detected;
    onEvent(SttSpeechActiveChanged(detected));
  }

  // 区切られた発話を順に取り出し、文字化して通知する
  void _drainAndTranscribe(sherpa.VoiceActivityDetector vad) {
    while (!vad.isEmpty()) {
      final segment = vad.front();
      vad.pop();

      // 発話と判定される前に話していた分を、区切りの頭へ補う
      final samples = _headKeeper.prependHead(segment);

      final stopwatch = Stopwatch()..start();
      final text = _transcribe(samples);
      stopwatch.stop();

      onEvent(SttTranscribed(
        text: text,
        durationSec: samples.length / _kSampleRate,
        elapsedMs: stopwatch.elapsedMilliseconds,
      ));
    }
  }

  // 1発話ぶんの音声サンプルを日本語テキストに変換する
  String _transcribe(Float32List samples) {
    final stream = _recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: _kSampleRate);
      _recognizer.decode(stream);
      return _recognizer.getResult(stream).text;
    } finally {
      stream.free();
    }
  }

  // PCM16 little-endian の生バイトを [-1, 1] の Float32 へ
  Float32List _pcm16ToFloat32(Uint8List bytes) {
    final sampleCount = bytes.length ~/ _kBytesPerSample;
    final view = ByteData.sublistView(bytes);
    final out = Float32List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      out[i] =
          view.getInt16(i * _kBytesPerSample, Endian.little) / _kInt16Amplitude;
    }
    return out;
  }

  // サンプルは [-1,1] に正規化済みなので、絶対値の最大がそのまま音量になる
  double _peakLevel(Float32List samples) {
    var maxAbs = 0.0;
    for (final sample in samples) {
      final abs = sample < 0 ? -sample : sample;
      if (abs > maxAbs) maxAbs = abs;
    }
    return maxAbs;
  }
}

// ============================================================
// _SpeechHeadKeeper — 発話と判定される前の声を、区切りの頭へ補う
//
//   本番の VAD は判定前の音を約1秒しか残さず、間を挟んだ話し始めが落ちるため、
//   3秒未満の間でつながる声らしい区間の先頭まで、覚えておいた音を足す。
// ============================================================
class _SpeechHeadKeeper {
  // 声らしいかを見る補助の VAD。発話とみなす最短の長さをほぼ0にして、窓ごとの判定をそのまま使う
  sherpa.VoiceActivityDetector? _voiceProbe;

  // 直近の窓（古い順）。位置は _historyStartPosition から窓の長さずつ進む
  final ListQueue<_HistoryWindow> _history = ListQueue<_HistoryWindow>();
  int _historyStartPosition = 0;

  // 本番の VAD に渡したサンプル数（＝次の窓の開始位置）
  int _position = 0;

  // これより前にはさかのぼらない位置（前の区切りの終わり・録音の切れ目）
  int _lookbackFloor = 0;

  static const int _maxHistoryWindows =
      _kHeadHistorySeconds * _kSampleRate ~/ _kVadWindow;
  static const int _maxLookbackSamples = _kHeadLookbackSeconds * _kSampleRate;
  static const int _minSilenceSamples =
      (_kMinSilenceDuration * _kSampleRate) ~/ 1;
  // 補助の VAD は声らしいと判定するまでに1窓ぶん遅れるため、先頭の手前にも少し余白を足す
  static const int _paddingSamples = 2 * _kVadWindow;

  // ---------------------------------
  // 始める・切れ目を入れる・片付ける
  // ---------------------------------

  // 本番の VAD を作り直したとき（位置が0から数え直しになる）
  void start(String sileroPath) {
    _voiceProbe?.free();
    _voiceProbe = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: sileroPath,
          threshold: _kVadThreshold,
          minSilenceDuration: 0.001,
          minSpeechDuration: 0.001,
          maxSpeechDuration: _kMaxSpeechDuration,
        ),
        sampleRate: _kSampleRate,
        numThreads: 1,
      ),
      bufferSizeInSeconds: _kVadBufferSeconds,
    );
    _history.clear();
    _historyStartPosition = 0;
    _position = 0;
    _lookbackFloor = 0;
  }

  // 本番の VAD を使い回して録音をやり直したとき。前の録音の音は補わない
  void markBoundary() {
    _lookbackFloor = _position;
  }

  void release() {
    _voiceProbe?.free();
    _voiceProbe = null;
    _history.clear();
  }

  // ---------------------------------
  // 窓ごとの記録（音と、声らしかったか）
  // ---------------------------------
  void acceptWindow(Float32List window) {
    final probe = _voiceProbe;
    if (probe == null) return;

    probe.acceptWaveform(window);
    final voiced = probe.isDetected();
    // 補助の VAD が区切った発話は使わないので捨てる
    probe.clear();

    _history.addLast(_HistoryWindow(samples: window, voiced: voiced));
    _position += window.length;
    // 上限を超えた古い窓から捨てる
    while (_history.length > _maxHistoryWindows) {
      _historyStartPosition += _history.removeFirst().samples.length;
    }
  }

  // ---------------------------------
  // 区切りの頭へ、判定前の声を足したサンプルを返す
  // ---------------------------------
  Float32List prependHead(sherpa.SpeechSegment segment) {
    final segmentStart = segment.start;
    final headStart = _findHeadStart(segmentStart);

    // 次の区切りが、この区切りと重なる音を補わないようにする
    _lookbackFloor = segmentStart + segment.samples.length;

    if (headStart == null || headStart >= segmentStart) return segment.samples;

    final head = _collectSamples(from: headStart, to: segmentStart);
    final combined = Float32List(head.length + segment.samples.length);
    combined.setAll(0, head);
    combined.setAll(head.length, segment.samples);
    return combined;
  }

  // 区切りの開始位置から過去へさかのぼり、つながっている声らしい区間の先頭を探す
  int? _findHeadStart(int segmentStart) {
    // 前の区切り・録音の切れ目・覚えている範囲・さかのぼれる上限のうち、いちばん新しい位置より前には行かない
    final floor = [
      _lookbackFloor,
      _historyStartPosition,
      segmentStart - _maxLookbackSamples,
    ].reduce((latest, position) => position > latest ? position : latest);

    int? earliestVoicedStart;
    // 直近で声らしかった位置（区切りの開始は声の続きとして扱う）
    var nearestVoicedStart = segmentStart;

    var windowEnd = _position;
    for (final window in _history.toList().reversed) {
      final windowStart = windowEnd - window.samples.length;
      windowEnd = windowStart;

      // 区切りの中の窓は見ない
      if (windowStart >= segmentStart) continue;
      // さかのぼってよい位置より前には行かない
      if (windowStart < floor) break;
      // 無音が本番の基準（3秒）以上続いたら、別の発話とみなして止める
      if (nearestVoicedStart - windowStart >= _minSilenceSamples) break;

      if (window.voiced) {
        earliestVoicedStart = windowStart;
        nearestVoicedStart = windowStart;
      }
    }

    if (earliestVoicedStart == null) return null;
    final padded = earliestVoicedStart - _paddingSamples;
    return padded > floor ? padded : floor;
  }

  // 覚えている窓から [from, to) の音を取り出す
  Float32List _collectSamples({required int from, required int to}) {
    final out = Float32List(to - from);
    var windowStart = _historyStartPosition;
    for (final window in _history) {
      final windowEnd = windowStart + window.samples.length;
      final copyStart = from > windowStart ? from : windowStart;
      final copyEnd = to < windowEnd ? to : windowEnd;
      if (copyStart < copyEnd) {
        out.setRange(
          copyStart - from,
          copyEnd - from,
          window.samples,
          copyStart - windowStart,
        );
      }
      if (windowEnd >= to) break;
      windowStart = windowEnd;
    }
    return out;
  }
}

// 覚えておく1窓ぶんの音と、声らしかったか
class _HistoryWindow {
  const _HistoryWindow({required this.samples, required this.voiced});
  final Float32List samples;
  final bool voiced;
}
