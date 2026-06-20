import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

// ============================================================
// 案C 検証スパイク（使い捨て）
//   record(PCM16/16k/mono) → CircularBuffer 相当の累積
//     → sherpa 内蔵 Silero VAD で区切り
//     → OfflineRecognizer(nemoCtc) で文字化
//   研究ブランチ research/stt-sherpa-builtin-vad 用。合否確定後に破棄する。
//
//   モデルは Step 3 で adb push 済みの想定:
//     <ApplicationSupport>/stt_caseC/{model.int8.onnx, tokens.txt, silero_vad.onnx}
//   ApplicationSupport は Android では /data/user/0/jp.momeo.momeo/files。
// ============================================================

// VAD に与える1ウィンドウのサンプル数（Silero/16kHz の既定）
const int _kVadWindow = 512;
// 入力サンプリングレート
const int _kSampleRate = 16000;
// モデル配置ディレクトリ名（Step 3 と一致させる）
const String _kModelDir = 'stt_caseC';

// 1発話の転写結果
class _Segment {
  _Segment({
    required this.index,
    required this.durationSec,
    required this.elapsedMs,
    required this.text,
  });

  final int index;
  final double durationSec;
  final int elapsedMs;
  final String text;
}

class SttCaseCSpikeSection extends StatefulWidget {
  const SttCaseCSpikeSection({super.key});

  @override
  State<SttCaseCSpikeSection> createState() => _SttCaseCSpikeSectionState();
}

class _SttCaseCSpikeSectionState extends State<SttCaseCSpikeSection> {
  final AudioRecorder _recorder = AudioRecorder();

  sherpa.OfflineRecognizer? _recognizer;
  sherpa.VoiceActivityDetector? _vad;
  StreamSubscription<Uint8List>? _sub;

  // VAD へ窓単位で渡すための累積バッファ
  final List<double> _floatBuf = <double>[];

  bool _initializing = false;
  bool _initialized = false;
  bool _recording = false;
  bool _draining = false;

  int _segCounter = 0;
  final List<_Segment> _segments = <_Segment>[];
  final List<String> _logs = <String>[];

  // ---------------------------------
  // ログ
  // ---------------------------------

  void _log(String message) {
    final now = DateTime.now();
    final ts =
        '${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    debugPrint('[stt-caseC] $ts $message');
    if (!mounted) return;
    setState(() {
      _logs.insert(0, '$ts  $message');
      if (_logs.length > 120) _logs.removeLast();
    });
  }

  // ---------------------------------
  // 初期化（モデル読み込み）
  // ---------------------------------

  Future<void> _initialize() async {
    if (_initializing || _initialized) return;
    setState(() => _initializing = true);
    try {
      sherpa.initBindings();
      _log('initBindings 完了');

      final supportDir = await getApplicationSupportDirectory();
      final base = '${supportDir.path}/$_kModelDir';
      final modelPath = '$base/model.int8.onnx';
      final tokensPath = '$base/tokens.txt';
      final sileroPath = '$base/silero_vad.onnx';
      _log('モデルディレクトリ: $base');

      // NeMo CTC（単一ファイル）の OfflineRecognizer
      final recognizerConfig = sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          nemoCtc: sherpa.OfflineNemoEncDecCtcModelConfig(model: modelPath),
          tokens: tokensPath,
          numThreads: 2,
          debug: true,
        ),
      );
      _recognizer = sherpa.OfflineRecognizer(recognizerConfig);
      _log('OfflineRecognizer(nemoCtc) 生成 OK');

      // sherpa 内蔵 Silero VAD
      final vadConfig = sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: sileroPath,
          minSilenceDuration: 0.25,
          minSpeechDuration: 0.25,
        ),
        numThreads: 1,
        sampleRate: _kSampleRate,
      );
      _vad = sherpa.VoiceActivityDetector(
        config: vadConfig,
        bufferSizeInSeconds: 30,
      );
      _log('VoiceActivityDetector(silero) 生成 OK');

      setState(() => _initialized = true);
    } catch (e) {
      _log('初期化失敗: $e');
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  // ---------------------------------
  // 録音の開始/停止
  // ---------------------------------

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!_initialized) {
      _log('未初期化。先に「初期化」を実行してください');
      return;
    }

    final granted = await _recorder.hasPermission();
    if (!granted) {
      _log('マイク権限が許可されていません（RECORD_AUDIO）');
      return;
    }

    _vad?.reset();
    _vad?.clear();
    _floatBuf.clear();

    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _kSampleRate,
      numChannels: 1,
    );

    try {
      final stream = await _recorder.startStream(config);
      _sub = stream.listen(
        _onAudio,
        onError: (Object e) => _log('録音ストリームエラー: $e'),
      );
      setState(() => _recording = true);
      _log('録音開始（pcm16 / ${_kSampleRate}Hz / mono）');
    } catch (e) {
      _log('録音開始失敗: $e');
    }
  }

  Future<void> _stopRecording() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder.stop();
    } catch (_) {}

    // 末尾に残った発話を VAD から押し出す
    _vad?.flush();
    await _drainVad();

    setState(() => _recording = false);
    _log('録音停止');
  }

  // ---------------------------------
  // 音声チャンク受信 → Float32 化 → 窓単位で VAD へ
  // ---------------------------------

  void _onAudio(Uint8List bytes) {
    final floats = _pcm16ToFloat32(bytes);
    _floatBuf.addAll(floats);

    final vad = _vad;
    if (vad == null) return;

    while (_floatBuf.length >= _kVadWindow) {
      final window = Float32List.fromList(_floatBuf.sublist(0, _kVadWindow));
      _floatBuf.removeRange(0, _kVadWindow);
      vad.acceptWaveform(window);
    }

    _drainVad();
  }

  // PCM16 little-endian の生バイトを [-1, 1] の Float32 へ
  Float32List _pcm16ToFloat32(Uint8List bytes) {
    final count = bytes.length ~/ 2;
    final out = Float32List(count);
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < count; i++) {
      out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  // ---------------------------------
  // VAD が切り出した発話を順に転写
  // ---------------------------------

  Future<void> _drainVad() async {
    if (_draining) return;
    _draining = true;
    try {
      final vad = _vad;
      final recognizer = _recognizer;
      if (vad == null || recognizer == null) return;

      while (!vad.isEmpty()) {
        final segment = vad.front();
        vad.pop();
        _transcribe(recognizer, segment.samples);
        // UI を更新する余地を作る
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _draining = false;
    }
  }

  void _transcribe(sherpa.OfflineRecognizer recognizer, Float32List samples) {
    final sw = Stopwatch()..start();
    final stream = recognizer.createStream();
    stream.acceptWaveform(samples: samples, sampleRate: _kSampleRate);
    recognizer.decode(stream);
    final text = recognizer.getResult(stream).text;
    stream.free();
    sw.stop();

    final seg = _Segment(
      index: ++_segCounter,
      durationSec: samples.length / _kSampleRate,
      elapsedMs: sw.elapsedMilliseconds,
      text: text,
    );
    if (!mounted) return;
    setState(() => _segments.insert(0, seg));
    _log(
      'seg#${seg.index}  ${seg.durationSec.toStringAsFixed(1)}s  '
      '${seg.elapsedMs}ms  "${text.isEmpty ? '(空)' : text}"',
    );
  }

  // ---------------------------------
  // 破棄
  // ---------------------------------

  @override
  void dispose() {
    _sub?.cancel();
    _recorder.dispose();
    _vad?.free();
    _recognizer?.free();
    super.dispose();
  }

  // ---------------------------------
  // ビルド
  // ---------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 操作ボタン
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _initialized || _initializing ? null : _initialize,
                  child: Text(
                    _initialized
                        ? '初期化済み'
                        : (_initializing ? '初期化中…' : '初期化'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _initialized ? _toggleRecording : null,
                  child: Text(_recording ? '停止' : '録音開始'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _recording ? '● 録音中' : '待機中',
            style: theme.textTheme.labelMedium?.copyWith(
              color: _recording ? Colors.red : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Divider(height: 24),

          // セグメント結果
          Text('セグメント（新しい順）', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: _segments.isEmpty
                ? const Center(child: Text('まだ転写結果はありません'))
                : ListView.separated(
                    itemCount: _segments.length,
                    separatorBuilder: (_, _) => const Divider(height: 8),
                    itemBuilder: (context, index) {
                      final seg = _segments[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'seg#${seg.index}  '
                            '${seg.durationSec.toStringAsFixed(1)}s  '
                            '→ ${seg.elapsedMs}ms',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            seg.text.isEmpty ? '(空)' : seg.text,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      );
                    },
                  ),
          ),
          const Divider(height: 24),

          // ログ
          Text('ログ（新しい順）', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, index) => Text(
                  _logs[index],
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFeatures: const [],
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
