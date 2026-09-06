import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/models/listening_sheet_tab.dart';
import 'package:momeo/repositories/app_settings_repository.dart';

// ============================================================
// backgroundRecordingProvider — バックグラウンド録音の設定を一元管理する
//
//   端末に保存されている「ユーザーがバックグラウンド録音を有効に
//   したいと思っているか」を読み書きする。実際にバックグラウンドで録れるか
//   （マイク権限やフォアグラウンドサービスの状態）は OS 側が持つため、
//   ここが扱うのはあくまでユーザーの意思だけ。
//
//   画面を離れても設定は保ち続けるので autoDispose にはしない。
// ============================================================

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>((ref) {
  return AppSettingsRepository();
});

// ============================================================
// listeningSheetTabOrderProvider — 下端シートのタブの並び順
//
//   画面には既定順をすぐ返し、端末に保存された順序を読み込めたら置き換える。
//   並び替えは画面へ即座に反映してから保存する。
// ============================================================

final listeningSheetTabOrderProvider =
    NotifierProvider<ListeningSheetTabOrderNotifier, List<ListeningSheetTab>>(
      ListeningSheetTabOrderNotifier.new,
    );

class ListeningSheetTabOrderNotifier extends Notifier<List<ListeningSheetTab>> {
  late AppSettingsRepository _repository;

  // 読み込み中にユーザーが並び替えた場合、古い読み込み結果で上書きしないための世代
  var _revision = 0;

  @override
  List<ListeningSheetTab> build() {
    _repository = ref.watch(appSettingsRepositoryProvider);
    unawaited(_restoreSavedOrder(_revision));
    return ListeningSheetTab.defaultOrder;
  }

  Future<void> _restoreSavedOrder(int startedAtRevision) async {
    final savedOrder = await _repository.listeningSheetTabOrder();
    if (startedAtRevision != _revision) return;
    state = savedOrder;
  }

  // ReorderableListView が渡す挿入位置へタブを移す
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.length) return;

    // 前から後ろへ動かす場合、先に元要素が抜けるぶんを補正する
    var destinationIndex = newIndex;
    if (oldIndex < destinationIndex) destinationIndex--;
    if (destinationIndex < 0) destinationIndex = 0;
    if (destinationIndex >= state.length) {
      destinationIndex = state.length - 1;
    }
    if (destinationIndex == oldIndex) return;

    final reordered = [...state];
    final movedTab = reordered.removeAt(oldIndex);
    reordered.insert(destinationIndex, movedTab);

    _revision++;
    state = List.unmodifiable(reordered);
    unawaited(_repository.saveListeningSheetTabOrder(state));
  }
}

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
