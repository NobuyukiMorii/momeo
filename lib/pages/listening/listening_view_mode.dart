// ============================================================
// 一覧画面のモード
// ============================================================
sealed class ListeningViewMode {
  const ListeningViewMode();
}

// ---------------------------------
// 通常の一覧（キーワードで絞り込む）
// ---------------------------------
class BrowsingMemos extends ListeningViewMode {
  const BrowsingMemos({this.keywords = const []});

  // 検索フィールドから取り込んだ、照合に使う語
  final List<String> keywords;
}

// ---------------------------------
// 選択済みのメモへの操作（このモードに入った瞬間の選択を一覧に出し続ける）
// ---------------------------------
class OperatingSelectedMemos extends ListeningViewMode {
  // 渡された集合を複製して閉じ込める（選択の増減に引きずられないようにする）
  OperatingSelectedMemos({required Set<int> pinnedMemoIds})
    : pinnedMemoIds = Set.unmodifiable(pinnedMemoIds);

  // 一覧に出し続けるメモの id（入った後は選択が減っても変えない）
  final Set<int> pinnedMemoIds;
}
