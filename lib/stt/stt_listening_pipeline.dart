import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'package:momeo/stt/stt_transcriber.dart';

// ============================================================
// リスニングの録音パイプライン（録音 → 区切り → 文字化）
//
//   マイクの音を連続キャプチャし、発話ごとに区切って日本語テキストに変換し、
//   1発話確定するたびに onText で通知する部品。画面（listening_page）から
//   録音まわりの詳細を分離するためのもの。
//
//   ■ 配線（dev catalog「文字化」セクションと同じ）
//   🎤 record（PCM16 / 16kHz / モノラル）
//     ↓ Float32 に変換し、512サンプル窓で供給
//   sherpa 内蔵 Silero VAD（無音 1.5秒で発話終了を検出）
//     ↓ 1発話ぶんの音声チャンク
//   SttTranscriber.transcribe()（100〜300ms）
//     ↓
//   onText(テキスト) で通知（空文字の扱いは受け手が決める）
//
//   ■ 所有関係
//   - この部品が所有する: AudioRecorder・VAD（dispose で後始末する）
//   - 借り物: SttTranscriber（Step 9 の共有エンジン。dispose しない）
//
//   ※ 生成前に sherpa.initBindings() が済んでいること（Step 9 の provider が
//     エンジン準備で先に呼ぶため、エンジン取得後に作れば自然に満たされる）。
//   ※ 転写はメインスレッドで動く（spike 指摘C・②）。取りこぼしの実機計測用に
//     発話長と転写時間を debug ログに出す。
// ============================================================

const int _kSampleRate = 16000; // 1秒あたりのサンプル数
const int _kBytesPerSample = 2; // PCM16 = 1サンプル2バイト
const int _kInt16Amplitude = 32768; // PCM16 の正規化基準（2^15）
const int _kVadWindow = 512; // VAD に1回で渡すサンプル数（16kHz の Silero 用）
const double _kVadBufferSeconds = 60; // VAD 内部バッファ（秒）。maxSpeechDuration を余裕で収める

// VAD の区切り設定
//   無音 1.5秒 = メモ確定条件（旧仕様 pauseFor と同じ値。担い手が VAD に変わった）
const double _kMinSilenceDuration = 1.5;
const double _kMinSpeechDuration = 0.25;
const double _kMaxSpeechDuration = 30.0;

class SttListeningPipeline {
  SttListeningPipeline({
    required SttTranscriber transcriber,
    required String sileroPath,
    required this.onText,
    this.onSpeechActiveChanged,
  })  : _transcriber = transcriber,
        _vad = _createVad(sileroPath);

  // 文字化エンジン（借り物）。後始末は Step 9 の provider の担当
  final SttTranscriber _transcriber;

  // 1発話確定するたびに呼ばれる通知先（リスニング画面の _addMemo につなぐ）
  final void Function(String text) onText;

  // VAD の「発話中かどうか」が切り替わるたびに呼ばれる通知先（任意）
  //   true: 発話の開始を検出した（発話開始から約 minSpeechDuration 後）
  //   false: 発話の終了を検出した（無音 minSilenceDuration 後 = 確定と同時）
  final void Function(bool isActive)? onSpeechActiveChanged;

  final AudioRecorder _recorder = AudioRecorder();
  final sherpa.VoiceActivityDetector _vad;
  StreamSubscription<Uint8List>? _subscription;

  // VAD へ窓単位で渡すための累積バッファ
  final List<double> _floatBuffer = <double>[];

  bool _running = false;

  // 直近に通知した「発話中かどうか」（変化したときだけ通知するため）
  bool _speechActive = false;

  // silero の住所から VAD を生成する
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
  // リスニングの開始 / 停止
  // ---------------------------------

  Future<void> start() async {
    if (_running) return;

    // 権限フロー（Step 2）で許可済みの前提だが、念のため確認する
    final granted = await _recorder.hasPermission();
    if (!granted) {
      throw StateError('マイクの利用が許可されていません（RECORD_AUDIO）');
    }

    _vad.clear();
    _floatBuffer.clear();

    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _kSampleRate,
      numChannels: 1,
    );
    final stream = await _recorder.startStream(config);
    _subscription = stream.listen(
      _onAudioChunk,
      onError: (Object error) =>
          debugPrint('[sttPipeline] 録音ストリームのエラー: $error'),
    );
    _running = true;
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    await _subscription?.cancel();
    _subscription = null;
    _notifySpeechActive(detected: false);
    try {
      await _recorder.stop();
    } catch (_) {
      // 停止時の例外は致命的でないため無視
    }

    // 末尾に残った発話を VAD から押し出して文字化する
    _vad.flush();
    _drainAndTranscribe();
  }

  // ---------------------------------
  // 音声チャンクの受信
  //   ① Float32 へ変換 → ② 512サンプル窓で VAD に供給 → ③ 区切り → 文字化
  // ---------------------------------

  void _onAudioChunk(Uint8List bytes) {
    // ① PCM16（整数）を Float32（小数）に変換して貯める
    _floatBuffer.addAll(_pcm16ToFloat32(bytes));

    // ② 512サンプルたまるごとに VAD へ渡す
    while (_floatBuffer.length >= _kVadWindow) {
      final window = Float32List.fromList(_floatBuffer.sublist(0, _kVadWindow));
      _floatBuffer.removeRange(0, _kVadWindow);
      _vad.acceptWaveform(window);
    }

    // 「発話中かどうか」の変化を通知する（区切り＝onText より先に知らせる）
    _notifySpeechActive(detected: _vad.isDetected());

    // ③ 区切られた発話を取り出して文字化する
    _drainAndTranscribe();
  }

  // 発話中かどうかが前回通知から変化していたら通知する
  void _notifySpeechActive({required bool detected}) {
    if (detected == _speechActive) return;
    _speechActive = detected;
    onSpeechActiveChanged?.call(detected);
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

  // VAD が区切った発話チャンクを順に取り出し、文字化して onText へ渡す
  void _drainAndTranscribe() {
    while (!_vad.isEmpty()) {
      final segment = _vad.front();
      _vad.pop();

      final durationSec = segment.samples.length / _kSampleRate;

      // 転写時間を計測する（spike 指摘C・②の取りこぼし判定に使う）
      final stopwatch = Stopwatch()..start();
      final text = _transcriber.transcribe(segment.samples);
      stopwatch.stop();

      if (kDebugMode) {
        debugPrint(
          '[sttPipeline] 発話 ${durationSec.toStringAsFixed(1)}s'
          ' → 転写 ${stopwatch.elapsedMilliseconds}ms'
          ' → 「$text」',
        );
      }
      onText(text);
    }
  }

  // ---------------------------------
  // 後始末（借り物の transcriber には触らない）
  // ---------------------------------

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
    _vad.free();
  }
}
