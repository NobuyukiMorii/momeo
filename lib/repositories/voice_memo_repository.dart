import 'package:drift/drift.dart';
import 'package:momeo/database/app_database.dart';

// ---------------------------------
// メモの保存・取得・削除
// ---------------------------------
class VoiceMemoRepository {
  VoiceMemoRepository(this._db);

  final AppDatabase _db;

  // ---------------------------------
  // 全件取得（新しい順）
  // ---------------------------------
  Future<List<VoiceMemo>> findAll() {
    final query = _db.select(_db.voiceMemos)
      ..orderBy([(memo) => OrderingTerm.desc(memo.createdAt)]);
    return query.get();
  }

  // ---------------------------------
  // 1件追加し、採番された id を返す（挿入は Companion を使う）
  // ---------------------------------
  Future<int> insert({required String content, required DateTime createdAt}) {
    return _db.into(_db.voiceMemos).insert(
          VoiceMemosCompanion.insert(
            content: content,
            createdAt: createdAt,
          ),
        );
  }

  // ---------------------------------
  // 指定した id の1件を削除する
  // ---------------------------------
  Future<void> delete(int id) {
    return (_db.delete(_db.voiceMemos)..where((memo) => memo.id.equals(id))).go();
  }

  // ---------------------------------
  // 指定した id をまとめて削除する
  // ---------------------------------
  Future<void> deleteByIds(List<int> ids) {
    // --- 空なら DB に触れずに終える
    if (ids.isEmpty) return Future.value();
    // --- 指定された id だけを消す
    return (_db.delete(_db.voiceMemos)..where((memo) => memo.id.isIn(ids))).go();
  }

  // ---------------------------------
  // 全件削除する
  // ---------------------------------
  Future<void> deleteAll() {
    return _db.delete(_db.voiceMemos).go();
  }
}
