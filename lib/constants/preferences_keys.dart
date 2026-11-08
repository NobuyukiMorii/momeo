// SharedPreferences で使用する型
enum PreferenceType {
  boolean,
  stringList;

  String get label => switch (this) {
    PreferenceType.boolean => 'bool',
    PreferenceType.stringList => 'List<String>',
  };
}

// キー名と型をペアで管理するエントリ
class PreferenceEntry {
  final String key;
  final PreferenceType type;
  const PreferenceEntry({required this.key, required this.type});
}

// SharedPreferences で使用するキーを一元管理する
// all の並び順がコンソール画面の表示順になる
abstract final class PreferencesKeys {
  // 初回起動かどうか
  static const isFirstLaunch = 'is_first_launch';

  static const all = [
    // 初回起動かどうか
    PreferenceEntry(key: isFirstLaunch, type: PreferenceType.boolean),
  ];
}
