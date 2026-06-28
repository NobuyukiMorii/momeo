import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:momeo/stt/stt_model_provisioner.dart';
import 'package:momeo/stt/stt_transcriber.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

// ============================================================
// 文字化（NeMo CTC）の動作確認セクション
//   マイク → VAD（Step 5）で発話を区切り → 区切ったチャンクを NeMo で日本語テキストに
//   変換して表示する。1チャンクあたりの変換時間（ms）も並べて、体感の速さを確かめる。
//
//   ■ 流れ
//   ① record の PCM16 を Float32 に変換し、512サンプル窓で VAD に供給（VAD 区切りと同じ）
//   ② VAD が区切った発話チャンクを取り出す
//   ③ そのチャンクを SttTranscriber に渡して文字化し、結果と所要時間を記録する
//
//   ※ ここは dev catalog 上での単発確認。エンジンの常駐（1個保持）・起動時準備は Step 9。
//   ※ 文字化はメインスレッドで動く（重い処理の isolate 化は実機計測しだい・Step 9/10）。
// ============================================================

const int _kSampleRate = 16000; // 1秒あたりのサンプル数
const int _kBytesPerSample = 2; // PCM16 = 1サンプル2バイト
const int _kInt16Amplitude = 32768; // PCM16 の正規化基準（2^15）
const int _kVadWindow = 512; // VAD に1回で渡すサンプル数（16kHz の Silero 用）
const double _kVadBufferSeconds = 60; // VAD 内部バッファ（秒）。maxSpeechDuration を余裕で収める

// VAD の区切り設定（VAD セクションの初期値と同じ。ここでは固定で使う）
const double _kMinSilenceDuration = 1.5;
const double _kMinSpeechDuration = 0.25;
const double _kMaxSpeechDuration = 30.0;

// 文字化した1発話の記録
class _Transcript {
  _Transcript({
    required this.index,
    required this.durationSec,
    required this.elapsedMs,
    required this.text,
  });

  final int index; // 通し番号
  final double durationSec; // 発話の長さ（秒）
  final int elapsedMs; // 文字化にかかった時間（ミリ秒）
  final String text; // 認識された日本語テキスト
}

class SttTranscriptionSection extends StatefulWidget {
  const SttTranscriptionSection({super.key});

  @override
  State<SttTranscriptionSection> createState() =>
      _SttTranscriptionSectionState();
}

class _SttTranscriptionSectionState extends State<SttTranscriptionSection> {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;

  sherpa.VoiceActivityDetector? _vad;
  SttTranscriber? _transcriber;

  // VAD へ窓単位で渡すための累積バッファ
  final List<double> _floatBuffer = <double>[];

  bool _preparing = true; // モデル準備中
  bool _ready = false; // VAD・認識器ともに生成済みで録音可能
  bool _recording = false;

  int _counter = 0;
  final List<_Transcript> _transcripts = <_Transcript>[];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  // ---------------------------------
  // 準備：モデルの住所を窓口から受け取り、VAD と認識器を生成する
  // ---------------------------------

  Future<void> _prepare() async {
    try {
      sherpa.initBindings();

      // Step 6 の窓口で3ファイルの住所・整合性をまとめて取得する
      final models = await SttModelProvisioner().provision();

      // silero（VAD 用）が無いと区切れない
      if (!models.silero.isValid) {
        throw StateError('silero_vad.onnx が見つかりません（VAD 区切り不可）');
      }
      // NeMo（本体・tokens）が無いと文字化できない
      if (!models.nemoModel.isValid || !models.nemoTokens.isValid) {
        throw StateError(
          'NeMo モデルが未配置です。「STT → モデル配置」が OK か確認してください',
        );
      }

      _createVad(models.silero.path);
      _transcriber = SttTranscriber.create(
        modelPath: models.nemoModel.path,
        tokensPath: models.nemoTokens.path,
      );

      if (!mounted) return;
      setState(() {
        _preparing = false;
        _ready = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _errorMessage = '準備に失敗しました: $error';
      });
    }
  }

  // silero の住所から VAD を生成する
  void _createVad(String sileroPath) {
    _vad?.free();
    _vad = sherpa.VoiceActivityDetector(
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
  // 録音の開始 / 停止
  // ---------------------------------

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!_ready) return;

    final granted = await _recorder.hasPermission();
    if (!granted) {
      setState(() => _errorMessage = 'マイクの利用が許可されていません（RECORD_AUDIO）');
      return;
    }

    // 前回分を消してから始める
    _vad?.clear();
    _floatBuffer.clear();

    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _kSampleRate,
      numChannels: 1,
    );

    try {
      final stream = await _recorder.startStream(config);
      _subscription = stream.listen(
        _onAudioChunk,
        onError: (Object error) =>
            setState(() => _errorMessage = '録音ストリームのエラー: $error'),
      );
      setState(() {
        _recording = true;
        _errorMessage = null;
      });
    } catch (error) {
      setState(() => _errorMessage = '録音の開始に失敗しました: $error');
    }
  }

  Future<void> _stopRecording() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // 停止時の例外は致命的でないため無視
    }

    // 末尾に残った発話を VAD から押し出して文字化する
    _vad?.flush();
    _drainAndTranscribe();

    setState(() => _recording = false);
  }

  // ---------------------------------
  // 音声チャンクの受信
  //   ① Float32 へ変換 → ② 512サンプル窓で VAD に供給 → ③ 区切り → 文字化
  // ---------------------------------

  void _onAudioChunk(Uint8List bytes) {
    final vad = _vad;
    if (vad == null) return;

    // ① PCM16（整数）を Float32（小数）に変換して貯める
    _floatBuffer.addAll(_pcm16ToFloat32(bytes));

    // ② 512サンプルたまるごとに VAD へ渡す
    while (_floatBuffer.length >= _kVadWindow) {
      final window = Float32List.fromList(_floatBuffer.sublist(0, _kVadWindow));
      _floatBuffer.removeRange(0, _kVadWindow);
      vad.acceptWaveform(window);
    }

    // ③ 区切られた発話を取り出して文字化する
    _drainAndTranscribe();
  }

  // PCM16 little-endian の生バイトを [-1, 1] の Float32 へ
  Float32List _pcm16ToFloat32(Uint8List bytes) {
    final sampleCount = bytes.length ~/ _kBytesPerSample;
    final view = ByteData.sublistView(bytes);
    final out = Float32List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      out[i] = view.getInt16(i * _kBytesPerSample, Endian.little) / _kInt16Amplitude;
    }
    return out;
  }

  // VAD が区切った発話チャンクを順に取り出し、その場で文字化して記録する
  void _drainAndTranscribe() {
    final vad = _vad;
    final transcriber = _transcriber;
    if (vad == null || transcriber == null) return;

    while (!vad.isEmpty()) {
      final segment = vad.front();
      vad.pop();

      final durationSec = segment.samples.length / _kSampleRate;

      // 文字化の所要時間を測る（メインスレッドでの単発変換）
      final stopwatch = Stopwatch()..start();
      final text = transcriber.transcribe(segment.samples);
      stopwatch.stop();

      _transcripts.insert(
        0,
        _Transcript(
          index: ++_counter,
          durationSec: durationSec,
          elapsedMs: stopwatch.elapsedMilliseconds,
          text: text,
        ),
      );
    }
    if (mounted) setState(() {});
  }

  // ---------------------------------
  // 破棄
  // ---------------------------------

  @override
  void dispose() {
    _subscription?.cancel();
    _recorder.dispose();
    _vad?.free();
    _transcriber?.dispose();
    super.dispose();
  }

  // ---------------------------------
  // ビルド
  // ---------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_preparing) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'マイクの音を VAD で発話ごとに区切り、NeMo で日本語テキストに変換します。\n'
          '各発話の「長さ・変換時間・認識テキスト」を表示します。',
          style: theme.textTheme.bodyMedium,
        ),
        const Divider(height: 32),

        // ---------------------------------
        // 録音の開始 / 停止
        // ---------------------------------
        FilledButton(
          onPressed: _ready ? _toggleRecording : null,
          child: Text(_recording ? '停止' : '録音開始'),
        ),
        const SizedBox(height: 8),
        Text(
          _recording ? '● 録音中' : '待機中',
          style: theme.textTheme.labelMedium?.copyWith(
            color: _recording ? Colors.red : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Divider(height: 32),

        // ---------------------------------
        // 文字化の結果
        // ---------------------------------
        Text(
          '認識結果（${_transcripts.length} 件・新しい順）',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (_transcripts.isEmpty)
          Text(
            'まだ認識結果はありません',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final transcript in _transcripts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'seg#${transcript.index}   '
                    '${transcript.durationSec.toStringAsFixed(1)} 秒   '
                    '変換 ${transcript.elapsedMs} ms',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    transcript.text.isEmpty ? '（空）' : transcript.text,
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),

        // ---------------------------------
        // エラー表示
        // ---------------------------------
        if (_errorMessage != null) ...[
          const Divider(height: 32),
          Text(
            _errorMessage!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
