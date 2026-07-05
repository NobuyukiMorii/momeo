import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:momeo/database/app_database.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/providers/database_providers.dart';
import 'package:momeo/providers/stt_providers.dart';
import 'package:momeo/repositories/voice_memo_repository.dart';
import 'package:momeo/stt/stt_listening_pipeline.dart';
import 'package:momeo/stt/stt_model_provisioner.dart';
import 'package:momeo/widgets/voice_card.dart';

// =====================================================================
// ListeningPage — リスニング画面
// =====================================================================
class ListeningPage extends ConsumerStatefulWidget {
  const ListeningPage({super.key});

  @override
  ConsumerState<ListeningPage> createState() => _ListeningPageState();
}

class _ListeningPageState extends ConsumerState<ListeningPage> {
  // ---------------------------------
  // メモの保存・取得を担うデータ係（initState で Provider から受け取る）
  // ---------------------------------
  late final VoiceMemoRepository _repository;

  // ---------------------------------
  // 確定済みメモ一覧（新しいものを先頭に並べる）
  // ---------------------------------
  final List<VoiceMemo> _memos = [];

  // 録音 → 区切り → 文字化までを担う、画面破棄まで動き続けるパイプライン
  SttListeningPipeline? _pipeline;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(voiceMemoRepositoryProvider);
    _loadMemos();
    _startListening();
  }

  // ---------------------------------
  // 画面に入ったら共有STTエンジンの準備完了を待ってリスニングを自動開始する（ボタンなし）
  // ---------------------------------
  Future<void> _startListening() async {
    try {
      // 全画面で共有しているSTTエンジンを受け取る（ここでは新規作成しない）
      final transcriber = await ref.read(sttEngineProvider.future);
      // VADモデル（silero）のパスを取得する
      final sileroPath = await SttModelProvisioner().ensureSilero();
      if (!mounted) return;

      final pipeline = SttListeningPipeline(
        transcriber: transcriber,
        sileroPath: sileroPath,
        onText: _addMemo, // VAD の発話終了 → 文字化 → メモ保存（確定トリガー）
      );
      await pipeline.start();

      if (!mounted) {
        await pipeline.dispose();
        return;
      }
      _pipeline = pipeline;
    } catch (error) {
      // 準備待ち画面やエラー表示はまだ無い。ここではログに記録するだけ
      debugPrint('[listening] リスニングを開始できませんでした: $error');
    }
  }

  @override
  void dispose() {
    _pipeline?.dispose();
    super.dispose();
  }

  // ---------------------------------
  // 保存済みメモを読み込んで一覧を更新する
  // ---------------------------------
  Future<void> _loadMemos() async {
    final memos = await _repository.findAll();
    if (!mounted) return;
    setState(() {
      _memos
        ..clear()
        ..addAll(memos);
    });
  }

  // ---------------------------------
  // 確定テキストをメモとして保存し、一覧を更新する
  // 音声のテキスト化が済んだら、ここに確定テキストを渡す（方式を問わない接続点）
  // 空文字（無音・雑音による空の認識結果）はここで弾く
  // ---------------------------------
  Future<void> _addMemo(String text) async {
    final content = text.trim();
    if (content.isEmpty) return;
    await _repository.insert(content: content, createdAt: DateTime.now());
    await _loadMemos();
  }

  // ---------------------------------
  // 日時を表示用の文字列にする（例: 2026/4/20 23:13）
  // ---------------------------------
  String _formatDateTime(DateTime dateTime) {
    return DateFormat('y/M/d HH:mm').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.xl),
          itemCount: _memos.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xl),
          itemBuilder: (context, index) {
            // ---------------------------------
            // 確定済みメモカード（日時付き）
            // ---------------------------------
            final memo = _memos[index];
            return VoiceCard(
              text: memo.content,
              dateTime: _formatDateTime(memo.createdAt),
            );
          },
        ),
      ),
    );
  }
}
