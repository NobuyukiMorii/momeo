import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/database/app_database.dart';
import 'package:momeo/providers/database_providers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// ============================================================
// 発話の記録（認識したまま）と修正の記録（編集の前後）を見て、JSON で書き出すセクション
//   書き出したものを Mac に送り、どんな直しが多いかを眺めるために使う
// ============================================================

class StorageEditRecordsSection extends ConsumerStatefulWidget {
  const StorageEditRecordsSection({super.key});

  @override
  ConsumerState<StorageEditRecordsSection> createState() => _StorageEditRecordsSectionState();
}

class _StorageEditRecordsSectionState extends ConsumerState<StorageEditRecordsSection> {
  List<VoiceMemo> _memos = const [];
  List<Utterance> _utterances = const [];
  List<MemoEdit> _edits = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---------------------------------
  // 読み込み
  // ---------------------------------
  Future<void> _load() async {
    final repository = ref.read(voiceMemoRepositoryProvider);
    final memos = await repository.findAll();
    final utterances = await repository.findAllUtterances();
    final edits = await repository.findAllEdits();
    if (!mounted) return;
    setState(() {
      // 上から順（古い順）に並べ直す
      _memos = memos.reversed.toList();
      _utterances = utterances;
      _edits = edits;
      _loading = false;
    });
  }

  // ---------------------------------
  // 書き出し
  // ---------------------------------
  // 今の本文（段落ごと）・発話の記録・修正の記録を1つの JSON にする
  String _buildJson() {
    final records = {
      'exportedAt': DateTime.now().toIso8601String(),
      'memos': [
        for (final memo in _memos)
          {'id': memo.id, 'createdAt': memo.createdAt.toIso8601String(), 'content': memo.content},
      ],
      'utterances': [
        for (final utterance in _utterances)
          {
            'id': utterance.id,
            'recognizedAt': utterance.recognizedAt.toIso8601String(),
            'durationSec': utterance.durationSec,
            'memoId': utterance.memoId,
            'content': utterance.content,
          },
      ],
      'edits': [
        for (final edit in _edits)
          {
            'id': edit.id,
            'editedAt': edit.editedAt.toIso8601String(),
            'before': edit.beforeText,
            'after': edit.afterText,
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(records);
  }

  Future<void> _share(BuildContext buttonContext) async {
    // iPad では共有シートを出す位置が必要（await の前に求めておく）
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/momeo_edit_records.json');
    await file.writeAsString(_buildJson());
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      sharePositionOrigin: origin,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);

    return ListView(
      children: [
        // ---------------------------------
        // 件数と書き出し
        // ---------------------------------
        ListTile(
          title: Text('段落 ${_memos.length}・発話 ${_utterances.length}・修正 ${_edits.length}'),
          trailing: Builder(
            builder: (buttonContext) => IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'JSON で書き出す',
              onPressed: () => _share(buttonContext),
            ),
          ),
        ),
        const Divider(height: 1),
        // ---------------------------------
        // 修正の記録（新しい順）
        // ---------------------------------
        if (_edits.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('まだ修正の記録はありません', style: theme.textTheme.bodyMedium),
          ),
        for (final edit in _edits.reversed) ...[
          ListTile(
            title: Text(edit.afterText.isEmpty ? '（消した）' : edit.afterText),
            subtitle: Text('前: ${edit.beforeText}\n${edit.editedAt}'),
            isThreeLine: true,
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}
