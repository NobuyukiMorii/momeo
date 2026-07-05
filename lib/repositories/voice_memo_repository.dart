import 'package:drift/drift.dart';
import 'package:momeo/database/app_database.dart';

// ---------------------------------
// VoiceMemoRepository — メモの保存・取得・削除を担うデータ係
//
// drift の作法（取得は VoiceMemo / 挿入は VoiceMemosCompanion）を
// このクラスの中に隠し、画面からは単純なメソッドだけ見えるようにする。
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
  // 全件削除する
  // ---------------------------------
  Future<void> deleteAll() {
    return _db.delete(_db.voiceMemos).go();
  }
}
