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

  // 初回起動かどうか
  static const isFirstLaunch = 'is_first_launch';

  // バックグラウンド録音を有効にしているか
  static const backgroundRecordingEnabled = 'background_recording_enabled';

  // バックグラウンド録音を一度でも有効にしたことがあるか
  static const backgroundRecordingEverEnabled = 'background_recording_ever_enabled';

  static const all = [
    // 初回起動かどうか
    PreferenceEntry(key: isFirstLaunch, type: PreferenceType.boolean),
    // バックグラウンド録音を有効にしているか
    PreferenceEntry(
      key: backgroundRecordingEnabled,
      type: PreferenceType.boolean,
    ),
    // バックグラウンド録音を一度でも有効にしたことがあるか
    PreferenceEntry(
      key: backgroundRecordingEverEnabled,
      type: PreferenceType.boolean,
    ),
  ];
}
