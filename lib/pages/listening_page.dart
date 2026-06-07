import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:momeo/database/app_database.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/providers/database_providers.dart';
import 'package:momeo/repositories/voice_memo_repository.dart';
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

  @override
  void initState() {
    super.initState();
    _repository = ref.read(voiceMemoRepositoryProvider);
    _loadMemos();
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
  // ---------------------------------
  // ignore: unused_element
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
          // ---------------------------------
          // 先頭のアクティブカード + 確定済みメモ
          // ---------------------------------
          itemCount: _memos.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xl),
          itemBuilder: (context, index) {
            // ---------------------------------
            // 先頭はアクティブカード（リスニング中インジケーター。日時なし）
            // ---------------------------------
            if (index == 0) {
              return const VoiceCard(text: '', isListening: true);
            }

            // ---------------------------------
            // 確定済みメモカード（日時付き）
            // ---------------------------------
            final memo = _memos[index - 1];
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
