import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/database/app_database.dart';
import 'package:momeo/repositories/voice_memo_repository.dart';

// ---------------------------------
// databaseProvider — アプリ全体で共有する AppDatabase を提供する
// 1個だけ生成し、破棄時に close する
// ---------------------------------
final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

// ---------------------------------
// voiceMemoRepositoryProvider — メモのデータ係を提供する
// databaseProvider の AppDatabase を使って組み立てる
// ---------------------------------
final voiceMemoRepositoryProvider = Provider<VoiceMemoRepository>((ref) {
  return VoiceMemoRepository(ref.watch(databaseProvider));
});
