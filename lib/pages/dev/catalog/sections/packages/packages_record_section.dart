import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

// ============================================================
// record パッケージの動作確認セクション
//   マイクを PCM16 / 16kHz / モノラルで連続キャプチャし、
//   「音が取れているか」を音量メーターと受信量カウンタで可視化する。
//   ここでは録音（PCM の取得）だけを行い、区切り・文字化はしない。
//
//   ■ 用語の補足
//   - サンプル: マイクが拾う音の波を一定間隔で測った「1回ぶんの値」。
//   - サンプリングレート: 1秒あたり何回その値を測るか（下の _kSampleRate）。
//   - PCM: その測定値を順番に並べただけの、圧縮していない生の音声データ。
//     16bit（＝1サンプルを2バイトの整数）で記録するので「PCM16」と呼ぶ。
// ============================================================

// 録音設定（オンデバイス STT が期待する形式に合わせる）
const int _kSampleRate = 16000; // 1秒あたりに音を測る回数（16000回 = 16kHz）
const int _kNumChannels = 1; // チャンネル数。1 = モノラル（マイク1本ぶん）

// PCM16 は 1サンプル = 16bit = 2バイト。バイト数とサンプル数の変換に使う。
// ※ encoder を PCM16 以外に変えたら、この値と getInt16 / _kInt16Amplitude も見直すこと。
const int _kBytesPerSample = 2;

// PCM16（符号付き16bit）のサンプルが取りうる最大の大きさ = 2^15。
// 振幅を 0.0〜1.0 に正規化するときの基準にする。
// ※ encoder を PCM16 以外に変えたら、この値も見直すこと。
const int _kInt16Amplitude = 32768;

class PackagesRecordSection extends StatefulWidget {
  const PackagesRecordSection({super.key});

  @override
  State<PackagesRecordSection> createState() => _PackagesRecordSectionState();
}

class _PackagesRecordSectionState extends State<PackagesRecordSection> {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;

  bool _recording = false;

  // 直近チャンクの音量（0.0〜1.0）。メーター表示に使う
  double _level = 0.0;

  // 受信量の累計
  int _totalSamples = 0;
  int _totalBytes = 0;

  // 直近のエラーメッセージ（あれば表示する）
  String? _errorMessage;

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


  // ---------------------------------
  // 録音の開始
  // ---------------------------------

  Future<void> _startRecording() async {
    setState(() => _errorMessage = null);

    // マイクの利用許可を確認（未許可ならここで要求される）
    final granted = await _recorder.hasPermission();
    if (!granted) {
      setState(() => _errorMessage = 'マイクの利用が許可されていません（RECORD_AUDIO）');
      return;
    }

    // PCM16 / 16kHz / モノラルで録音ストリームを開く
    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _kSampleRate,
      numChannels: _kNumChannels,
    );

    try {
      final stream = await _recorder.startStream(config);
      _subscription = stream.listen(
        _onAudioChunk,
        onError: (Object error) {
          setState(() => _errorMessage = '録音ストリームのエラー: $error');
        },
      );
      setState(() {
        _recording = true;
        _totalSamples = 0;
        _totalBytes = 0;
        _level = 0.0;
      });
    } catch (error) {
      setState(() => _errorMessage = '録音の開始に失敗しました: $error');
    }
  }

  // ---------------------------------
  // 録音の停止
  // ---------------------------------

  Future<void> _stopRecording() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // 停止時の例外は致命的でないため握りつぶす
    }
    setState(() {
      _recording = false;
      _level = 0.0;
    });
  }

  // ---------------------------------
  // 音声チャンクの受信
  //   届いた PCM16 の生バイトから受信量と音量を計算する
  // ---------------------------------

  void _onAudioChunk(Uint8List bytes) {
    // 届くのは PCM の生バイト列。1サンプル = 2バイトなので、
    // バイト数を割るとサンプル数（＝音を測った回数）になる。
    final sampleCount = bytes.length ~/ _kBytesPerSample;
    final peak = _peakLevel(bytes); // このチャンクの最大音量（0.0〜1.0）

    if (!mounted) return;
    setState(() {
      _totalBytes += bytes.length;
      _totalSamples += sampleCount;
      _level = peak;
    });
  }

  // このチャンクの中で「いちばん大きい音」を 0.0〜1.0 の割合で求める。
  // 各サンプルは -32768〜32767 の整数。その絶対値の最大を取り、
  // PCM16 の最大値で割って「どれくらい大きい音か」を 0〜1 に変換する（音量メーター用）。
  double _peakLevel(Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    final sampleCount = bytes.length ~/ _kBytesPerSample;
    var maxAbs = 0;
    for (var i = 0; i < sampleCount; i++) {
      // i 番目のサンプルを 16bit 整数として読む（2バイトずつ進む）
      final sample = view.getInt16(i * _kBytesPerSample, Endian.little).abs();
      if (sample > maxAbs) maxAbs = sample;
    }
    return maxAbs / _kInt16Amplitude; // 0.0（無音）〜1.0（最大音量）に正規化
  }

  // ---------------------------------
  // 破棄
  // ---------------------------------

  @override
  void dispose() {
    _subscription?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // ---------------------------------
  // ビルド
  // ---------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---------------------------------
        // 録音設定の表示
        // ---------------------------------
        Text('録音設定', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'PCM16 / ${_kSampleRate}Hz / '
          '${_kNumChannels == 1 ? 'モノラル' : '$_kNumChannels ch'}',
          style: theme.textTheme.bodyMedium,
        ),
        const Divider(height: 32),

        // ---------------------------------
        // 録音の開始 / 停止
        // ---------------------------------
        FilledButton(
          onPressed: _toggleRecording,
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
        // 音量メーター
        //   話すとバーが伸びれば、マイクの音が取れている
        // ---------------------------------
        Text('音量メーター', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _level,
            minHeight: 16,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '現在の音量: ${(_level * 100).toStringAsFixed(0)}%',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Divider(height: 32),

        // ---------------------------------
        // 受信量
        // ---------------------------------
        Text('受信量（録音開始からの累計）', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _StatRow(label: 'サンプル数', value: '$_totalSamples'),
        _StatRow(label: 'バイト数', value: '$_totalBytes'),
        // サンプル数 ÷ 1秒あたりの回数(16000) = おおよその録音秒数。
        // これが実際の経過時間と合えば「16kHz で取れている」と確認できる。
        _StatRow(
          label: '録音時間の目安',
          value: '${(_totalSamples / _kSampleRate).toStringAsFixed(1)} 秒',
        ),

        // ---------------------------------
        // エラー表示（あれば）
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

// ---------------------------------
// ラベルと値を左右に並べる1行
//   フォントを等幅にして数値を整列させる
// ---------------------------------

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
