// ---------------------------------
// 下端シートに表示するタブ
// ---------------------------------
enum ListeningSheetTab {
  // いつ録音するかの選択肢
  recordingOptions,

  // 選択中のメモへの操作（0 件でも表示する）
  selectionActions;

  // 保存が無いときに使う並び順（enum の宣言順）
  static List<ListeningSheetTab> get defaultOrder => values;

  // enum 名を変更しても保存済みの設定を壊さない、永続化専用の固定 ID
  String get storageId => switch (this) {
    recordingOptions => 'recording_options',
    selectionActions => 'selection_actions',
  };

  // 保存されている ID をタブへ戻す（知らない ID は古い設定として無視する）
  static ListeningSheetTab? fromStorageId(String storageId) {
    for (final tab in values) {
      if (tab.storageId == storageId) return tab;
    }
    return null;
  }

  // 保存値を現在のタブ構成に合わせる
  static List<ListeningSheetTab> restoreOrder(List<String>? storageIds) {
    final restored = <ListeningSheetTab>[];

    // 保存されていた順序を優先し、知らない ID と重複は除く
    for (final storageId in storageIds ?? const <String>[]) {
      final tab = fromStorageId(storageId);
      if (tab != null && !restored.contains(tab)) restored.add(tab);
    }

    // アップデートで増えたタブは、既存の並びを崩さず末尾へ補う
    for (final tab in values) {
      if (!restored.contains(tab)) restored.add(tab);
    }

    return List.unmodifiable(restored);
  }
}
