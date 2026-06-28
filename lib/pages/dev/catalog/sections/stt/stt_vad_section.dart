import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:momeo/stt/stt_model_provisioner.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

// ============================================================
// sherpa 内蔵 VAD（Silero）の動作確認セクション
//   record のマイク音声を VAD に流し込み、「発話ごとに区切られたチャンク」を取り出す。
//   区切りの設定値（無音の長さ等）をスライダーで調整しながら、区切り具合を確認する。
//   ここでは区切るところまで（文字化はしない）。
//
//   ■ 区切りの仕組み（箱）
//   ① record の PCM16（整数）を Float32（小数）に変換 …… VAD が読める形にする
//   ② 512サンプルずつ VAD に渡す
//   ③ VAD が「1発話ぶん終わった」と判断したチャンクを取り出す
// ============================================================

const int _kSampleRate = 16000; // 1秒あたりのサンプル数
const int _kBytesPerSample = 2; // PCM16 = 1サンプル2バイト
const int _kInt16Amplitude = 32768; // PCM16 の正規化基準（2^15）
const int _kVadWindow = 512; // VAD に1回で渡すサンプル数（16kHz の Silero 用）
const double _kVadBufferSeconds = 60; // VAD 内部バッファ（秒）。maxSpeechDuration(最大30秒)を余裕で収める

// 区切られた1発話の記録
class _Segment {
  _Segment({required this.index, required this.durationSec});

  final int index;
  final double durationSec;
}

class SttVadSection extends StatefulWidget {
  const SttVadSection({super.key});

  @override
  State<SttVadSection> createState() => _SttVadSectionState();
}

class _SttVadSectionState extends State<SttVadSection> {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;

  sherpa.VoiceActivityDetector? _vad;
  String? _modelPath;

  // VAD へ窓単位で渡すための累積バッファ
  final List<double> _floatBuffer = <double>[];

  // 区切りの調整パラメータ（初期値）
  //   minSilence: 主役。1.5秒は specs（listening_flow）由来
  //   maxSpeech : 安全弁。黙らず喋り続けた時だけ効く上限
  double _minSilenceDuration = 1.5;
  double _minSpeechDuration = 0.25;
  double _maxSpeechDuration = 30.0;

  bool _preparing = true; // モデル準備中
  bool _ready = false; // VAD 生成済みで録音可能
  bool _recording = false;

  int _segmentCounter = 0;
  final List<_Segment> _segments = <_Segment>[];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  // ---------------------------------
  // 準備：モデルをアセットから配置し、VAD を生成する
  // ---------------------------------

  Future<void> _prepare() async {
    try {
      sherpa.initBindings();
      _modelPath = await SttModelProvisioner().ensureSilero();
      _createVad();
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _ready = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _errorMessage = 'VAD の準備に失敗しました: $error';
      });
    }
  }

  // 現在のパラメータで VAD を生成する（パラメータ変更時は作り直す）
  void _createVad() {
    final path = _modelPath;
    if (path == null) return;

    _vad?.free();
    _vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: path,
          minSilenceDuration: _minSilenceDuration,
          minSpeechDuration: _minSpeechDuration,
          maxSpeechDuration: _maxSpeechDuration,
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

    // 末尾に残った発話を VAD から押し出して取り出す
    _vad?.flush();
    _drainSegments();

    setState(() => _recording = false);
  }

  // ---------------------------------
  // 音声チャンクの受信
  //   ① Float32 へ変換 → ② 512サンプル窓で VAD に供給 → ③ 区切りを取り出す
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

    // ③ 区切られた発話を取り出す
    _drainSegments();
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

  // VAD が区切った発話チャンクを順に取り出して記録する
  void _drainSegments() {
    final vad = _vad;
    if (vad == null) return;

    while (!vad.isEmpty()) {
      final segment = vad.front();
      vad.pop();
      final durationSec = segment.samples.length / _kSampleRate;
      _segments.insert(
        0,
        _Segment(index: ++_segmentCounter, durationSec: durationSec),
      );
    }
    if (mounted) setState(() {});
  }

  // ---------------------------------
  // パラメータ変更（録音停止中のみ）→ VAD を作り直す
  // ---------------------------------

  void _onSilenceChanged(double value) =>
      setState(() => _minSilenceDuration = value);
  void _onSpeechChanged(double value) =>
      setState(() => _minSpeechDuration = value);
  void _onMaxSpeechChanged(double value) =>
      setState(() => _maxSpeechDuration = value);

  void _applyParams() => _createVad();

  // ---------------------------------
  // 破棄
  // ---------------------------------

  @override
  void dispose() {
    _subscription?.cancel();
    _recorder.dispose();
    _vad?.free();
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
          'マイクの音を sherpa 内蔵 VAD に流し、発話ごとに区切ります。\n'
          'スライダーで区切り方を調整できます（録音停止中に変更 → 反映）。',
          style: theme.textTheme.bodyMedium,
        ),
        const Divider(height: 32),

        // ---------------------------------
        // 区切りの調整パラメータ
        // ---------------------------------
        Text('区切りの設定', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _ParamSlider(
          label: 'minSilenceDuration（無音で区切る・主役）',
          value: _minSilenceDuration,
          min: 0.1,
          max: 3.0,
          unit: '秒',
          enabled: !_recording,
          onChanged: _onSilenceChanged,
          onChangeEnd: (_) => _applyParams(),
        ),
        _ParamSlider(
          label: 'minSpeechDuration（これより短い音は無視）',
          value: _minSpeechDuration,
          min: 0.05,
          max: 1.0,
          unit: '秒',
          enabled: !_recording,
          onChanged: _onSpeechChanged,
          onChangeEnd: (_) => _applyParams(),
        ),
        _ParamSlider(
          label: 'maxSpeechDuration（強制区切りの上限・安全弁）',
          value: _maxSpeechDuration,
          min: 2.0,
          max: 30.0,
          unit: '秒',
          enabled: !_recording,
          onChanged: _onMaxSpeechChanged,
          onChangeEnd: (_) => _applyParams(),
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
        // 区切られた発話チャンク
        // ---------------------------------
        Text(
          '発話チャンク（${_segments.length} 件・新しい順）',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (_segments.isEmpty)
          Text(
            'まだ区切られた発話はありません',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final segment in _segments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'seg#${segment.index}   ${segment.durationSec.toStringAsFixed(1)} 秒',
                style: theme.textTheme.bodyMedium,
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

// ラベル付きのパラメータ調整スライダー
class _ParamSlider extends StatelessWidget {
  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label : ${value.toStringAsFixed(2)} $unit',
          style: theme.textTheme.bodySmall,
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: enabled ? onChanged : null,
          onChangeEnd: enabled ? onChangeEnd : null,
        ),
      ],
    );
  }
}
