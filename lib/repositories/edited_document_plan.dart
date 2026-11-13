import 'package:flutter/foundation.dart' show listEquals;
import 'package:momeo/database/app_database.dart';

// 編集を終えた文書の1段落（sourceIds は、その段落の文字が元々どのメモの文字だったか。出てくる順）
typedef EditedParagraph = ({String text, List<int> sourceIds});

// 編集の後の1段落を、どの行に保存するか（id が null なら新しい行を足す）
typedef PlannedParagraph = ({int? id, String content, DateTime createdAt});

// 1回の編集で変わった段落の、前後の文字列（複数の段落は改行でつなぐ）
typedef ChangedText = ({String before, String after});

// ============================================================
// EditedDocumentPlan — 編集を終えた文書を、段落ごとに DB の行へどう戻すかを決める
//
//   印が1つで、その行がまだ使われていない → その行の本文を書き換える
//   印が2つ以上（段落をつなげた）        → 一番古い行にまとめ、ほかの行は消す
//   印がすでに使われた行（段落を分けた）  → 新しい行にし、元の行の日時を引き継ぐ
//   印が無い（手で書き足した）            → 新しい行にし、上の段落の日時を引き継ぐ
//   文字が無い                            → 保存しない
// ============================================================
class EditedDocumentPlan {
  const EditedDocumentPlan._({
    required this.paragraphs,
    required this.deletedIds,
    required this.changedText,
    required this.hasChanges,
  });

  // 保存する段落（上から順）
  final List<PlannedParagraph> paragraphs;

  // どの段落にも使われなくなった行
  final List<int> deletedIds;

  // 修正の記録に残す文字列（段落の分け方だけが変わったときは null）
  final ChangedText? changedText;

  // 編集の前から何か変わったか（変わっていなければ保存しない）
  final bool hasChanges;

  // ---------------------------------
  // 編集の前の段落（上から順）と、編集の後の段落から組み立てる
  // ---------------------------------
  factory EditedDocumentPlan.build({
    required List<VoiceMemo> beforeMemos,
    required List<EditedParagraph> editedParagraphs,
  }) {
    final memosById = {for (final memo in beforeMemos) memo.id: memo};
    final planned = <PlannedParagraph>[];
    final usedIds = <int>{};

    for (final paragraph in editedParagraphs) {
      if (paragraph.text.trim().isEmpty) continue;
      final sources = [
        for (final id in paragraph.sourceIds)
          if (memosById[id] != null) memosById[id]!,
      ];
      final reused = _oldestUnused(sources, usedIds);
      if (reused != null) {
        usedIds.add(reused.id);
        planned.add((id: reused.id, content: paragraph.text, createdAt: reused.createdAt));
      } else {
        final createdAt = sources.firstOrNull?.createdAt ?? planned.lastOrNull?.createdAt ?? DateTime.now();
        planned.add((id: null, content: paragraph.text, createdAt: createdAt));
      }
    }

    final beforeTexts = [for (final memo in beforeMemos) memo.content];
    final afterTexts = [for (final paragraph in planned) paragraph.content];
    final sameRows = listEquals(
      [for (final memo in beforeMemos) memo.id],
      [for (final paragraph in planned) paragraph.id],
    );
    return EditedDocumentPlan._(
      paragraphs: planned,
      deletedIds: [
        for (final memo in beforeMemos)
          if (!usedIds.contains(memo.id)) memo.id,
      ],
      changedText: _changedText(beforeTexts, afterTexts),
      hasChanges: !sameRows || !listEquals(beforeTexts, afterTexts),
    );
  }

  // まだ使っていない行のうち、一番古いもの（日時、同じなら並び順）
  static VoiceMemo? _oldestUnused(List<VoiceMemo> sources, Set<int> usedIds) {
    final unused = sources.where((memo) => !usedIds.contains(memo.id)).toList()
      ..sort((a, b) {
        final byDate = a.createdAt.compareTo(b.createdAt);
        return byDate != 0 ? byDate : a.position.compareTo(b.position);
      });
    return unused.firstOrNull;
  }

  // 前後の段落を比べ、先頭と末尾から同じ段落を除いた残り（変わった段落）
  static ChangedText? _changedText(List<String> before, List<String> after) {
    var head = 0;
    while (head < before.length && head < after.length && before[head] == after[head]) {
      head++;
    }
    var tail = 0;
    while (tail < before.length - head &&
        tail < after.length - head &&
        before[before.length - 1 - tail] == after[after.length - 1 - tail]) {
      tail++;
    }
    final changedBefore = before.sublist(head, before.length - tail);
    final changedAfter = after.sublist(head, after.length - tail);
    // 段落の分け方だけが変わったとき（文字は同じ）は、記録しない
    if (changedBefore.join() == changedAfter.join()) return null;
    return (before: changedBefore.join('\n'), after: changedAfter.join('\n'));
  }
}
