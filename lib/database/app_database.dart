import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

// ---------------------------------
// VoiceMemos — 一覧の段落（1行が1段落）を保存するテーブル
// ---------------------------------
class VoiceMemos extends Table {
  // 自動採番の主キー
  IntColumn get id => integer().autoIncrement()();

  // 段落の本文
  TextColumn get content => text()();

  // 段落の日時（声の段落は話し始めた日時。分けた段落は元の段落の日時を引き継ぐ）
  DateTimeColumn get createdAt => dateTime()();

  // 一覧での並び順（小さいほど上。分けた段落は日時が同じになるので、日時ではなくこれで並べる）
  IntColumn get position => integer().withDefault(const Constant(0))();
}

// ---------------------------------
// Utterances — 認識したままの発話（書いたら書き換えない）
// ---------------------------------
class Utterances extends Table {
  // 自動採番の主キー
  IntColumn get id => integer().autoIncrement()();

  // 認識したままの文字列（前後の空白だけ落としたもの）
  TextColumn get content => text()();

  // 確定した日時
  DateTimeColumn get recognizedAt => dateTime()();

  // 発話の長さ（秒）
  RealColumn get durationSec => real()();

  // そのときつないだ段落の id（段落はあとでつながったり消えたりするので、今もあるとは限らない）
  IntColumn get memoId => integer()();
}

// ---------------------------------
// MemoEdits — 1回の編集で変わった段落の、前後の文字列
// ---------------------------------
class MemoEdits extends Table {
  // 自動採番の主キー
  IntColumn get id => integer().autoIncrement()();

  // 編集の前の、変わった段落の文字列（複数の段落は改行でつなぐ）
  TextColumn get beforeText => text()();

  // 編集の後の、変わった段落の文字列（全部消したときは空）
  TextColumn get afterText => text()();

  // 編集を終えた日時
  DateTimeColumn get editedAt => dateTime()();
}

// ---------------------------------
// AppDatabase — アプリのデータベース本体
// ---------------------------------
@DriftDatabase(tables: [VoiceMemos, Utterances, MemoEdits])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 2;

  // ---------------------------------
  // 版を上げたときの作り直し
  // ---------------------------------
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            // 並び順を足し、今ある段落には日時の順で振る
            await migrator.addColumn(voiceMemos, voiceMemos.position);
            await customStatement(
              'UPDATE voice_memos SET position = ('
              'SELECT COUNT(*) FROM voice_memos AS older '
              'WHERE older.created_at < voice_memos.created_at '
              'OR (older.created_at = voice_memos.created_at AND older.id < voice_memos.id))',
            );
            await migrator.createTable(utterances);
            await migrator.createTable(memoEdits);
          }
        },
      );

  // ---------------------------------
  // DB接続を開く（ファイル名を指定）
  // ---------------------------------
  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'momeo');
  }
}
