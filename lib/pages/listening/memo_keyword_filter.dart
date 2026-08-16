import 'package:momeo/database/app_database.dart';

// ---------------------------------
// キーワードを配列に変換
// ---------------------------------
List<String> parseMemoKeywords(String input) {
  // --- 入力文字列をならして、スペースで区切る
  final words = normalizeForMemoKeywordMatch(input).split(RegExp(r'\s+'));
  // --- 空文字列を取り除いて返す
  return [
    for (final word in words)
      if (word.isNotEmpty) word,
  ];
}

// ---------------------------------
// メモの絞り込み
// ---------------------------------
List<VoiceMemo> filterMemosByKeywords(
  List<VoiceMemo> memos,
  List<String> keywords,
) {
  // --- キーワードが空なら素通し
  if (keywords.isEmpty) return memos;
  // --- キーワードを含むメモだけを残す
  return [
    for (final memo in memos)
      // --- 本文がキーワードを含むかチェック
      if (_containsAnyKeyword(memo.content, keywords)) memo,
  ];
}

// ---------------------------------
// 本文がキーワードを含むかチェック
// ---------------------------------
bool _containsAnyKeyword(String content, List<String> keywords) {
  // --- 本文をならして、キーワードと照合
  final normalizedContent = normalizeForMemoKeywordMatch(content);
  // --- キーワードのいずれかが含まれていれば true
  return keywords.any(normalizedContent.contains);
}

// ---------------------------------
// メモの本文を照合用に正規化
// ---------------------------------
String normalizeForMemoKeywordMatch(String text) {
  // --- 全角の英数字・記号（！〜～）と半角（!〜~）のコードポイントの差
  const fullWidthOffset = 0xFEE0; // 全角から半角へのオフセット
  const fullWidthFirst = 0xFF01; // ！
  const fullWidthLast = 0xFF5E; // ～
  const ideographicSpace = 0x3000; // 全角スペース

  // --- 正規化した文字列を作成
  final normalized = StringBuffer();

  // --- 文字列を1つづつループ
  for (final rune in text.runes) { 

    // --- 全角の英数字・記号を半角に変換
    if (rune >= fullWidthFirst && rune <= fullWidthLast) { // 全角の英数字・記号
      // --- 半角に変換
      normalized.writeCharCode(rune - fullWidthOffset);

    } else if (rune == ideographicSpace) { // 全角スペース
      // --- 半角スペースに変換
      normalized.write(' ');

    } else { // それ以外の文字
      // --- それ以外の文字をそのまま追加
      normalized.writeCharCode(rune);
    }
  }

  // --- 正規化した文字列を小文字に変換して返す
  return normalized.toString().toLowerCase();
}
