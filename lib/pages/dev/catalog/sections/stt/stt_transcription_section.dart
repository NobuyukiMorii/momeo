import 'package:flutter/material.dart';
import 'package:momeo/stt/stt_audio_worker.dart';
import 'package:momeo/stt/stt_listening_pipeline.dart';
import 'package:momeo/stt/stt_model_provisioner.dart';

// ============================================================
// 文字化（NeMo CTC）の動作確認セクション
//   マイク → 音声 isolate（VAD の区切り → NeMo）→ 認識テキストの表示。
//   各発話の「長さ・変換時間・認識テキスト」を並べて体感の速さを確かめる。
//
//   リスニング画面と同じ配線（SttAudioWorker + SttListeningPipeline）を使うが、
//   ここでは確認用に専用の音声 isolate を立てる（共有エンジンには触れない）。
// ============================================================

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
  SttAudioWorker? _worker;
  SttListeningPipeline? _pipeline;

  bool _preparing = true; // モデル・音声 isolate の準備中
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
  // 準備：モデルの住所を窓口から受け取り、確認用の音声 isolate を立てる
  // ---------------------------------

  Future<void> _prepare() async {
    try {
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

      final worker = await SttAudioWorker.spawn(
        modelPath: models.nemoModel.path,
        tokensPath: models.nemoTokens.path,
      );

      if (!mounted) {
        await worker.dispose();
        return;
      }

      setState(() {
        _worker = worker;
        _pipeline = SttListeningPipeline(
          worker: worker,
          sileroPath: models.silero.path,
          onTranscribed: _onTranscribed,
        );
        _preparing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _errorMessage = '準備に失敗しました: $error';
      });
    }
  }

  // ---------------------------------
  // 録音の開始 / 停止
  // ---------------------------------

  Future<void> _toggleRecording() async {
    final pipeline = _pipeline;
    if (pipeline == null) return;

    try {
      if (_recording) {
        await pipeline.stop();
      } else {
        await pipeline.start();
      }
      if (!mounted) return;
      setState(() {
        _recording = !_recording;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = '録音を切り替えられませんでした: $error');
    }
  }

  // 音声 isolate から1発話ぶんの結果が届いたら記録する
  void _onTranscribed(SttTranscribed result) {
    _transcripts.insert(
      0,
      _Transcript(
        index: ++_counter,
        durationSec: result.durationSec,
        elapsedMs: result.elapsedMs,
        text: result.text,
      ),
    );
    if (mounted) setState(() {});
  }

  // ---------------------------------
  // 破棄
  // ---------------------------------

  @override
  void dispose() {
    _pipeline?.dispose();
    _worker?.dispose();
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
          onPressed: _pipeline == null ? null : _toggleRecording,
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
