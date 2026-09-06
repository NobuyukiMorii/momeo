import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

// ============================================================
// 音声処理（VAD の区切り・NeMo の文字化）を専用 isolate に閉じ込める窓口
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

// VAD の区切り設定。無音 1.5秒 = メモの確定条件
const double _kMinSilenceDuration = 1.5;
const double _kMinSpeechDuration = 0.25;
const double _kMaxSpeechDuration = 30.0;

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

  // NeMo は CTC 方式。この枠にモデル本体のパスを入れることで読み方が決まる
  static sherpa.OfflineRecognizer _createRecognizer({
    required String modelPath,
    required String tokensPath,
  }) {
    final config = sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        nemoCtc: sherpa.OfflineNemoEncDecCtcModelConfig(model: modelPath),
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
    } else {
      _vad?.free();
      _vad = _createVad(sileroPath);
      _sileroPath = sileroPath;
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

      final stopwatch = Stopwatch()..start();
      final text = _transcribe(segment.samples);
      stopwatch.stop();

      onEvent(SttTranscribed(
        text: text,
        durationSec: segment.samples.length / _kSampleRate,
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
