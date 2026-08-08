import 'package:shared_preferences/shared_preferences.dart';
import 'package:momeo/constants/preferences_keys.dart';

// ---------------------------------
// 端末に残すユーザー設定の読み書き
// ---------------------------------
class AppSettingsRepository {
  // ---------------------------------
  // バックグラウンド録音を有効/無効を取得する
  // ---------------------------------
  Future<bool> isBackgroundRecordingEnabled() async {
    // --- 保存先を開く
    final preferences = await SharedPreferences.getInstance();
    // --- 保存が無ければ無効として返す
    return preferences.getBool(PreferencesKeys.backgroundRecordingEnabled) ??
        false;
  }

  // ---------------------------------
  // バックグラウンド録音を一度でも有効にしたことがあるか
  // ---------------------------------
  Future<bool> hasEverEnabledBackgroundRecording() async {
    // --- 保存先を開く
    final preferences = await SharedPreferences.getInstance();
    // --- 保存が無ければ一度も無いとして返す
    return preferences.getBool(
          PreferencesKeys.backgroundRecordingEverEnabled,
        ) ??
        false;
  }

  // ---------------------------------
  // バックグラウンド録音の有効・無効を保存する
  // ---------------------------------
  Future<void> saveBackgroundRecordingEnabled(bool isEnabled) async {
    // --- 保存先を開く
    final preferences = await SharedPreferences.getInstance();
    // --- 有効・無効を保存する
    await preferences.setBool(
      PreferencesKeys.backgroundRecordingEnabled,
      isEnabled,
    );
    // --- 有効にしたときだけ、一度でも有効にした印を残す（確認ダイアログの判断に使う）
    if (isEnabled) {
      await preferences.setBool(
        PreferencesKeys.backgroundRecordingEverEnabled,
        true,
      );
    }
  }
}
