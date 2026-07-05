import 'package:momeo/database/app_database.dart';

// ============================================================
// MemoCardViewData — 確定済みメモカード1枚ぶんの表示用データ
//
//   「日時は同じ分の中で最初（時系列で最古）の1件だけに表示する」という
//   一覧の見せ方のルールを、純粋関数としてここに切り出す（単体テスト可能）。
// ============================================================

class MemoCardViewData {
  const MemoCardViewData({required this.memo, required this.showDateTime});

  final VoiceMemo memo;

  // このカードの右下に日時を表示するか
  final bool showDateTime;
}

// 新しい順に並んだメモ一覧から、カード表示用のデータを組み立てる
// 1つ後ろ（＝時系列で直前）のメモと分単位まで同じ日時なら、日時を出さない
List<MemoCardViewData> buildMemoCardViewData(List<VoiceMemo> memos) {
  return [
    for (var i = 0; i < memos.length; i++)
      MemoCardViewData(
        memo: memos[i],
        showDateTime: i + 1 >= memos.length ||
            !_isSameMinute(memos[i].createdAt, memos[i + 1].createdAt),
      ),
  ];
}

// 2つの日時が分単位まで同じか
bool _isSameMinute(DateTime a, DateTime b) {
  return a.year == b.year &&
      a.month == b.month &&
      a.day == b.day &&
      a.hour == b.hour &&
      a.minute == b.minute;
}
