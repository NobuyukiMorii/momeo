import 'package:intl/intl.dart';
import 'package:momeo/database/app_database.dart';

// ============================================================
// MemoCardViewData — 確定済みメモカード1枚ぶんの表示用データ
//
//   「時刻は同じ分の中で最後（時系列で最新）の1件だけに表示する」
//   「日付が変わる境目にはカードの上へ区切りを挟む」という一覧の
//   見せ方のルールを、純粋関数としてここに切り出す（単体テスト可能）。
// ============================================================

// 日付区切りの書式（今年のうちは年を省く）
final _dateLabelFormat = DateFormat('M月d日');
final _dateLabelFormatWithYear = DateFormat('y年M月d日');

class MemoCardViewData {
  const MemoCardViewData({
    required this.memo,
    required this.showDateTime,
    required this.dateSeparatorLabel,
  });

  final VoiceMemo memo;

  // このカードの右下に時刻を表示するか
  final bool showDateTime;

  // このカードの上に出す日付区切りの文字（区切りを出さないなら null）
  final String? dateSeparatorLabel;
}

// 新しい順に並んだメモ一覧から、カード表示用のデータを組み立てる
List<MemoCardViewData> buildMemoCardViewData(
  List<VoiceMemo> memos, {
  required DateTime today,
}) {
  // 一覧が1日ぶんに収まるなら、区切る相手がいないので日付を出さない
  final spansMultipleDays =
      memos.isNotEmpty &&
      !_isSameDay(memos.first.createdAt, memos.last.createdAt);

  return [
    for (var i = 0; i < memos.length; i++)
      MemoCardViewData(
        memo: memos[i],
        // 1つ手前（＝時系列で直後）のメモと分単位まで同じなら、時刻を出さない
        showDateTime:
            i == 0 ||
            !_isSameMinute(memos[i].createdAt, memos[i - 1].createdAt),
        // その日のいちばん古いメモ（＝画面では上端）にだけ区切りを持たせる
        dateSeparatorLabel: spansMultipleDays && _isOldestOfItsDay(memos, i)
            ? _buildDateSeparatorLabel(memos[i].createdAt, today)
            : null,
      ),
  ];
}

// 1つ後ろ（＝時系列で直前）のメモと日付が変わるか。一覧の末尾なら必ず変わる
bool _isOldestOfItsDay(List<VoiceMemo> memos, int index) {
  if (index == memos.length - 1) return true;
  return !_isSameDay(memos[index].createdAt, memos[index + 1].createdAt);
}

// 日付区切りに出す文字。直近の2日は日付を読まずに済むよう言葉で表す
String _buildDateSeparatorLabel(DateTime createdAt, DateTime today) {
  final yesterday = today.subtract(const Duration(days: 1));

  if (_isSameDay(createdAt, today)) return '今日';
  if (_isSameDay(createdAt, yesterday)) return '昨日';
  if (createdAt.year == today.year) return _dateLabelFormat.format(createdAt);
  return _dateLabelFormatWithYear.format(createdAt);
}

// 2つの日時が同じ日か
bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

// 2つの日時が分単位まで同じか
bool _isSameMinute(DateTime a, DateTime b) {
  return _isSameDay(a, b) && a.hour == b.hour && a.minute == b.minute;
}
