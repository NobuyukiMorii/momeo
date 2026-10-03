import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/database/app_database.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/providers/listening_providers.dart';
import 'package:momeo/widgets/listening_backdrop.dart';
import 'package:momeo/widgets/listening_recording_settings_panel.dart';
import 'package:momeo/widgets/listening_selection_bar.dart';
import 'package:momeo/widgets/native_memo_list.dart';

// 通知を出しておく時間
const _noticeDuration = Duration(milliseconds: 3600);

// 選択バーがせり上がる・引っ込む時間
const _selectionBarSlideDuration = Duration(milliseconds: 150);

// 選択中のメモをまとめてコピーしたときに、選択バーへ出す一言
const _selectionCopiedNotice = 'クリップボードにコピーしました';

// =====================================================================
// リスニング画面
// =====================================================================
class ListeningPage extends ConsumerStatefulWidget {
  const ListeningPage({super.key});

  @override
  ConsumerState<ListeningPage> createState() => _ListeningPageState();
}

class _ListeningPageState extends ConsumerState<ListeningPage>
    with SingleTickerProviderStateMixin {
  // ---------------------------------
  // 選択中のメモに関する状態
  // ---------------------------------
  // 選択中のメモの id
  final Set<int> _selectedMemoIds = {};

  // ---------------------------------
  // 選択バーに関する状態
  // ---------------------------------
  // 出具合（0 = 隠れきっている、1 = 出きっている）。バー自身と一覧の押し上げで共有する
  late final AnimationController _selectionBarController;

  // ---------------------------------
  // コピーの知らせに関する状態
  // ---------------------------------
  // 選択バーに出している一言（null なら出していない）
  String? _selectionBarNotice;
  // 選択バーの一言を引っ込めるタイマー
  Timer? _selectionBarNoticeTimer;

  @override
  void initState() {
    super.initState();
    _selectionBarController = AnimationController(
      vsync: this,
      duration: _selectionBarSlideDuration,
    );
  }

  @override
  void dispose() {
    _selectionBarNoticeTimer?.cancel(); // 選択バーの一言のタイマーを止める
    _selectionBarController.dispose();
    super.dispose();
  }

  // ---------------------------------
  // 選択バーにメッセージを出す
  // ---------------------------------
  void _showSelectionBarNotice(String notice) {
    setState(() => _selectionBarNotice = notice);
    _selectionBarNoticeTimer?.cancel();
    _selectionBarNoticeTimer = Timer(_noticeDuration, () {
      if (mounted) setState(_clearSelectionBarNotice);
    });
  }

  // ---------------------------------
  // 選択バーのメッセージを引っ込める
  // ---------------------------------
  void _clearSelectionBarNotice() {
    _selectionBarNoticeTimer?.cancel();
    _selectionBarNotice = null;
  }

  // ---------------------------------
  // 選択を変え、選択バーの表示状態を切り替える
  // ---------------------------------
  void _changeSelection(VoidCallback change) {
    setState(() {
      change();
      // 0 件になって選択バーを隠すときは、出していたメッセージも引っ込める
      if (_selectedMemoIds.isEmpty) _clearSelectionBarNotice();
    });
    // --- 1 件以上なら表示、0 件なら隠す（すでにその状態なら何も起きない）
    if (_selectedMemoIds.isEmpty) {
      _selectionBarController.reverse();
    } else {
      _selectionBarController.forward();
    }
  }

  // ---------------------------------
  // メモの選択・非選択
  // ---------------------------------
  void _toggleMemoSelection(int memoId) {
    _changeSelection(() {
      if (_selectedMemoIds.contains(memoId)) {
        // 選択中のメモを除外
        _selectedMemoIds.remove(memoId);
      } else {
        // 選択中のメモを追加
        _selectedMemoIds.add(memoId);
      }
    });
  }

  // ---------------------------------
  // 選択をすべて解除する（メモ自体は残る）
  // ---------------------------------
  void _clearMemoSelection() {
    _changeSelection(_selectedMemoIds.clear);
  }

  // ---------------------------------
  // 選択中のメモを削除する（DB からも消える。元に戻す手段は無い）
  // ---------------------------------
  Future<void> _deleteSelectedMemos() async {
    final targetIds = Set<int>.from(_selectedMemoIds);
    await ref.read(listeningProvider.notifier).deleteMemos(targetIds);
    if (!mounted) return;
    _changeSelection(() => _selectedMemoIds.removeAll(targetIds));
  }

  // ---------------------------------
  // 選択中のメモをまとめてコピーする（時系列順に空行1つでつなぐ）
  // ---------------------------------
  void _copySelectedMemos(List<VoiceMemo> selectedMemos) {
    // メモとメモのつなぎ目（コピーした文字列にもそのまま入る）
    const separator = '\n\n';
    // --- クリップボードにコピー
    final text = selectedMemos.map((memo) => memo.content).join(separator);
    Clipboard.setData(ClipboardData(text: text));
    // --- 選択バーに知らせを出す（選択はそのまま残す）
    _showSelectionBarNotice(_selectionCopiedNotice);
  }

  // ---------------------------------
  // メモ一覧
  // ---------------------------------
  Widget _buildMemoList({
    required ListeningState listening,
    required double safeAreaTop,
    required double recordingSettingsPanelHeight,
    required double safeAreaBottom,
  }) {
    return AnimatedBuilder(
      animation: _selectionBarController,
      builder: (context, child) => Padding(
        padding: EdgeInsets.only(
          // 上端は、録音設定パネルの状態行のぶん空ける。
          // 録音設定パネルを開いても覆いかぶさるだけなので、ここは動かさない
          top: safeAreaTop + recordingSettingsPanelHeight,
          // 下端は、選択バーの出入りと同じ動きで押し上げる
          bottom:
              safeAreaBottom +
              listeningSelectionBarPushUpHeight(
                slideProgress: _selectionBarController.value,
                safeAreaBottom: safeAreaBottom,
              ),
        ),
        child: child,
      ),
      child: NativeMemoList(memos: listening.memos),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ---------------------------------
    // リスニング状態
    // ---------------------------------
    final listening =
        ref.watch(listeningProvider).value ?? const ListeningState();

    // ---------------------------------
    // 選択中のメモ（memos は新しい順なので、時系列順に並べ替える）
    // ---------------------------------
    final selectedMemos = [
      for (final memo in listening.memos.reversed)
        if (_selectedMemoIds.contains(memo.id)) memo,
    ];

    // ---------------------------------
    // 安全領域
    // ---------------------------------
    final safeAreaTop = MediaQuery.paddingOf(context).top;
    final safeAreaBottom = MediaQuery.viewPaddingOf(context).bottom;

    // ---------------------------------
    // 録音設定パネルが閉じているときの高さ
    // ---------------------------------
    final recordingSettingsPanelHeight =
        listeningRecordingSettingsPanelCollapsedHeightOf(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // ---------------------------------
          // 背景レイヤー
          // ---------------------------------
          Positioned.fill(
            child: ListeningBackdrop(
              levelReader: () =>
                  ref.read(listeningProvider.notifier).latestLevel,
            ),
          ),
          // ---------------------------------
          // メモ一覧
          // ---------------------------------
          _buildMemoList(
            listening: listening,
            safeAreaTop: safeAreaTop,
            recordingSettingsPanelHeight: recordingSettingsPanelHeight,
            safeAreaBottom: safeAreaBottom,
          ),
          // ---------------------------------
          // 選択バー
          // ---------------------------------
          Positioned.fill(
            child: ListeningSelectionBar(
              slideAnimation: _selectionBarController,
              selectedCount: selectedMemos.length,
              onDeleteSelection: _deleteSelectedMemos,
              onCopySelection: () => _copySelectedMemos(selectedMemos),
              onClearSelection: _clearMemoSelection,
              notice: _selectionBarNotice,
            ),
          ),
          // ---------------------------------
          // 録音設定パネル
          // ---------------------------------
          const Positioned.fill(child: ListeningRecordingSettingsPanel()),
        ],
      ),
    );
  }
}
