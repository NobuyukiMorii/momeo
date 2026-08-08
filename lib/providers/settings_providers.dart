import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/repositories/app_settings_repository.dart';

// ============================================================
// backgroundRecordingProvider — バックグラウンド録音の設定を一元管理する
//
//   端末に保存されている「ユーザーがバックグラウンド録音を有効に
//   したいと思っているか」を読み書きする。実際に背面で録れるか
//   （マイク権限やフォアグラウンドサービスの状態）は OS 側が持つため、
//   ここが扱うのはあくまでユーザーの意思だけ。
//
//   画面を離れても設定は保ち続けるので autoDispose にはしない。
// ============================================================

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>((ref) {
  return AppSettingsRepository();
});

final backgroundRecordingProvider =
    AsyncNotifierProvider<
      BackgroundRecordingNotifier,
      BackgroundRecordingState
    >(BackgroundRecordingNotifier.new);

// ---------------------------------
// BackgroundRecordingState — バックグラウンド録音の設定（イミュータブル）
// ---------------------------------
class BackgroundRecordingState {
  const BackgroundRecordingState({
    required this.isEnabled,
    required this.hasEverEnabled,
  });

  // 今バックグラウンド録音を有効にしているか
  final bool isEnabled;

  // 一度でも有効にしたことがあるか（無効に戻しても false には戻らない）
  final bool hasEverEnabled;

  // 有効にする前に確認ダイアログを出す必要があるか。
  // 一度も有効にしていない間は、切り替えのたびに確認する
  bool get needsConfirmation => !hasEverEnabled;
}

// ---------------------------------
// BackgroundRecordingNotifier — 設定の読み込みと切り替え
// ---------------------------------
class BackgroundRecordingNotifier
    extends AsyncNotifier<BackgroundRecordingState> {
  late AppSettingsRepository _repository;

  @override
  Future<BackgroundRecordingState> build() async {
    _repository = ref.watch(appSettingsRepositoryProvider);

    return BackgroundRecordingState(
      isEnabled: await _repository.isBackgroundRecordingEnabled(),
      hasEverEnabled: await _repository.hasEverEnabledBackgroundRecording(),
    );
  }

  // ---------------------------------
  // 有効・無効を切り替える
  //
  // 確認ダイアログを出すかどうかの判断は画面側が needsConfirmation で行い、
  // ユーザーが承諾したあとでこのメソッドを呼ぶ
  // ---------------------------------
  Future<void> setEnabled(bool isEnabled) async {

    // 設定を保存する
    await _repository.saveBackgroundRecordingEnabled(isEnabled);

    // 状態を更新する
    state = AsyncData(
      BackgroundRecordingState(
        isEnabled: isEnabled,
        // 有効にした時点で「一度でも有効にした」印が立つ
        hasEverEnabled: isEnabled || (state.value?.hasEverEnabled ?? false),
      ),
    );
  }
}
