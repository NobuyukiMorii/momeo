import 'package:drift/drift.dart';
import 'package:momeo/database/app_database.dart';
import 'package:momeo/repositories/edited_document_plan.dart';

// ---------------------------------
// 段落・発話の記録・修正の記録の保存と取得
// ---------------------------------
class VoiceMemoRepository {
  VoiceMemoRepository(this._db);

  final AppDatabase _db;

  // ---------------------------------
  // 全件取得（新しい順。並び順の大きい方が新しい）
  // ---------------------------------
  Future<List<VoiceMemo>> findAll() {
    final query = _db.select(_db.voiceMemos)
      ..orderBy([
        (memo) => OrderingTerm.desc(memo.position),
        (memo) => OrderingTerm.desc(memo.id),
      ]);
    return query.get();
  }

  // ---------------------------------
  // 末尾に1段落足し、保存した段落を返す
  // ---------------------------------
  Future<VoiceMemo> insert({required String content, required DateTime createdAt}) {
    return _db.transaction(() async {
      final position = await _nextPosition();
      final id = await _db.into(_db.voiceMemos).insert(
            VoiceMemosCompanion.insert(
              content: content,
              createdAt: createdAt,
              position: Value(position),
            ),
          );
      return VoiceMemo(id: id, content: content, createdAt: createdAt, position: position);
    });
  }

  // 今ある段落の一番後ろの、次の並び順
  Future<int> _nextPosition() async {
    final maxPosition = _db.voiceMemos.position.max();
    final query = _db.selectOnly(_db.voiceMemos)..addColumns([maxPosition]);
    final row = await query.getSingle();
    final current = row.read(maxPosition);
    return current == null ? 0 : current + 1;
  }

  // ---------------------------------
  // 指定した id の本文を書き換える
  // ---------------------------------
  Future<void> updateContent({required int id, required String content}) {
    return (_db.update(_db.voiceMemos)..where((memo) => memo.id.equals(id)))
        .write(VoiceMemosCompanion(content: Value(content)));
  }

  // ---------------------------------
  // 編集を終えた文書を保存する（1つのトランザクションで行う）
  //   paragraphs は編集した範囲の段落（上から順）。それより後ろの段落は、今の順のまま後ろに並べる
  //   保存した段落を、上から順に返す
  // ---------------------------------
  Future<List<VoiceMemo>> saveEditedMemos({
    required List<PlannedParagraph> paragraphs,
    required List<int> deletedIds,
    required ChangedText? changedText,
  }) {
    return _db.transaction(() async {
      // --- 使わなくなった行を消す
      if (deletedIds.isNotEmpty) {
        await (_db.delete(_db.voiceMemos)..where((memo) => memo.id.isIn(deletedIds))).go();
      }

      // --- 段落ごとに書き換える・足す（並び順は上から 0, 1, 2…）
      final saved = [
        for (final (position, paragraph) in paragraphs.indexed)
          await _writeParagraph(paragraph, position: position),
      ];

      // --- 編集の間に増えた段落などは、今の順のまま後ろに並べ直す
      await _placeOthersAfter(saved);

      // --- 修正の記録を残す
      if (changedText != null) {
        await _db.into(_db.memoEdits).insert(MemoEditsCompanion.insert(
              beforeText: changedText.before,
              afterText: changedText.after,
              editedAt: DateTime.now(),
            ));
      }
      return saved;
    });
  }

  // 1段落を、id があればその行に書き換え、無ければ新しい行として足す
  Future<VoiceMemo> _writeParagraph(PlannedParagraph paragraph, {required int position}) async {
    final existingId = paragraph.id;
    final int id;
    if (existingId == null) {
      id = await _db.into(_db.voiceMemos).insert(VoiceMemosCompanion.insert(
            content: paragraph.content,
            createdAt: paragraph.createdAt,
            position: Value(position),
          ));
    } else {
      id = existingId;
      await (_db.update(_db.voiceMemos)..where((memo) => memo.id.equals(id)))
          .write(VoiceMemosCompanion(content: Value(paragraph.content), position: Value(position)));
    }
    return VoiceMemo(id: id, content: paragraph.content, createdAt: paragraph.createdAt, position: position);
  }

  // saved に入っていない段落を、今の順のまま saved の後ろの並び順に振り直す
  Future<void> _placeOthersAfter(List<VoiceMemo> saved) async {
    final savedIds = [for (final memo in saved) memo.id];
    final others = await (_db.select(_db.voiceMemos)
          ..where((memo) => memo.id.isNotIn(savedIds))
          ..orderBy([
            (memo) => OrderingTerm.asc(memo.position),
            (memo) => OrderingTerm.asc(memo.id),
          ]))
        .get();
    for (final (index, memo) in others.indexed) {
      final position = saved.length + index;
      if (memo.position == position) continue;
      await (_db.update(_db.voiceMemos)..where((row) => row.id.equals(memo.id)))
          .write(VoiceMemosCompanion(position: Value(position)));
    }
  }

  // ---------------------------------
  // 全件削除する（発話の記録と修正の記録も消す）
  // ---------------------------------
  Future<void> deleteAll() {
    return _db.transaction(() async {
      await _db.delete(_db.voiceMemos).go();
      await _db.delete(_db.utterances).go();
      await _db.delete(_db.memoEdits).go();
    });
  }

  // ---------------------------------
  // 発話の記録
  // ---------------------------------
  // 認識したままの発話を1件残す
  Future<void> insertUtterance({
    required String content,
    required DateTime recognizedAt,
    required double durationSec,
    required int memoId,
  }) {
    return _db.into(_db.utterances).insert(UtterancesCompanion.insert(
          content: content,
          recognizedAt: recognizedAt,
          durationSec: durationSec,
          memoId: memoId,
        ));
  }

  // 全件（古い順）
  Future<List<Utterance>> findAllUtterances() {
    return (_db.select(_db.utterances)..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
  }

  // ---------------------------------
  // 修正の記録（全件・古い順）
  // ---------------------------------
  Future<List<MemoEdit>> findAllEdits() {
    return (_db.select(_db.memoEdits)..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
  }
}
