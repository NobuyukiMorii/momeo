// SharedPreferences で使用する型
enum PreferenceType {
  boolean;

  String get label => switch (this) {
    PreferenceType.boolean => 'bool',
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
  static const isFirstLaunch = 'is_first_launch';

  static const all = [
    PreferenceEntry(key: isFirstLaunch, type: PreferenceType.boolean),
  ];
}
