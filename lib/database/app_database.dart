import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

// ---------------------------------
// VoiceMemos — 確定済みメモを保存するテーブル
// ---------------------------------
class VoiceMemos extends Table {
  // 自動採番の主キー
  IntColumn get id => integer().autoIncrement()();

  // 確定したテキスト
  TextColumn get content => text()();

  // 確定した日時
  DateTimeColumn get createdAt => dateTime()();
}

// ---------------------------------
// AppDatabase — アプリのデータベース本体
// ---------------------------------
@DriftDatabase(tables: [VoiceMemos])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  // ---------------------------------
  // DB接続を開く（ファイル名を指定）
  // ---------------------------------
  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'momeo');
  }
}
