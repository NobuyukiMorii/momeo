import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/database/app_database.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/providers/listening_providers.dart';
import 'package:momeo/widgets/listening_backdrop.dart';
import 'package:momeo/widgets/listening_memo_date_backdrop.dart';
import 'package:momeo/widgets/listening_recording_settings_panel.dart';
import 'package:momeo/widgets/listening_selection_bar.dart';
import 'package:momeo/widgets/native_memo_list.dart';

// 通知を出しておく時間
const _noticeDuration = Duration(milliseconds: 3600);

// 選択バーがせり上がる・引っ込む時間
const _selectionBarSlideDuration = Duration(milliseconds: 150);

// 選択中のメモをまとめてコピーしたときに、選択バーへ出す一言
const _selectionCopiedNotice = 'クリップボードにコピーしました';

// スクロールが止まってから、つまみの横の日付を消し始めるまでの時間
const _thumbDateHideDelay = Duration(milliseconds: 600);

// つまみの横の日付が現れる・消える時間
const _thumbDateFadeDuration = Duration(milliseconds: 200);

// スクロールつまみの横棒の太さ（ネイティブ側の描画とそろえる）
const _thumbThickness = 1.5;

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
  // 文字選択に関する状態
  // ---------------------------------
  // 文字選択は丸による選択と独立して、OS 側（ネイティブの一覧）が持つ
  final NativeMemoListController _nativeMemoListController =
      NativeMemoListController();

  // ---------------------------------
  // つまみの横の日付に関する状態
  // ---------------------------------
  // スクロールつまみの高さと、その高さにあるメモ（つまみの横の背景に、そのメモの日付を出す）
  // スクロールのたびに変わるので、画面全体を組み直さずに日付の層だけを動かす
  final ValueNotifier<MemoListThumb?> _thumb = ValueNotifier(null);
  // 日付はスクロールしている間だけ出し、止まってしばらくしたら消す
  final ValueNotifier<bool> _showsThumbDate = ValueNotifier(false);
  Timer? _thumbDateHideTimer;

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
    _thumb.dispose();
    _thumbDateHideTimer?.cancel();
    _showsThumbDate.dispose();
    _nativeMemoListController.dispose();
    super.dispose();
  }

  void _clearTextSelection() {
    _nativeMemoListController.clearSelection();
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
          top: safeAreaTop + recordingSettingsPanelHeight,
          bottom: listeningSelectionBarVisibleHeight(
            slideProgress: _selectionBarController.value,
            safeAreaBottom: safeAreaBottom,
          ),
        ),
        child: child,
      ),
      child: NativeMemoList(
        memos: listening.memos,
        selectedIds: Set.of(_selectedMemoIds),
        controller: _nativeMemoListController,
        typingMemoId: listening.typeInMemoId,
        typeFrom: listening.typeInFrom,
        speakingDots: _speakingDots(listening),
        onToggleSelection: _toggleMemoSelection,
        onThumbChanged: _onThumbChanged,
        onTypingComplete: _onTypingComplete,
      ),
    );
  }

  // 打ち出しの演出を使い切ったら、再表示で打ち直さないように知らせる
  void _onTypingComplete(int memoId) {
    if (!mounted) return;
    ref.read(listeningProvider.notifier).onTypingComplete(memoId);
  }

  // ---------------------------------
  // 発話中の「.」を出す場所
  // ---------------------------------
  // 発話が始まってから結果が届くまで出す。前の発話を打ち出している間は、打ち終わってから出す
  MemoSpeakingDots _speakingDots(ListeningState listening) {
    final waitingForText =
        listening.speechActive || listening.awaitingTranscription;
    if (!waitingForText || listening.typeInMemoId != null) {
      return MemoSpeakingDots.hidden;
    }
    // 追記先は発話の始まりで決まるので、出す場所も発話の途中では動かない
    return listening.appendTargetId != null
        ? MemoSpeakingDots.append
        : MemoSpeakingDots.newBlock;
  }

  // ---------------------------------
  // スクロールつまみの横に出す日付（本文の後ろの背景）
  // ---------------------------------
  void _onThumbChanged(MemoListThumb thumb) {
    _thumb.value = thumb;
    if (!thumb.scrolling) return;
    _showsThumbDate.value = true;
    _thumbDateHideTimer?.cancel();
    _thumbDateHideTimer = Timer(_thumbDateHideDelay, () {
      _showsThumbDate.value = false;
    });
  }

  // 一覧に無くなったメモの日付は出さない
  Widget _buildThumbDate({
    required List<VoiceMemo> memos,
    required double listTop,
  }) {
    return ListenableBuilder(
      listenable: Listenable.merge([_thumb, _showsThumbDate]),
      builder: (context, _) {
        final thumb = _thumb.value;
        final memo = memos
            .where((memo) => memo.id == thumb?.memoId)
            .firstOrNull;
        if (thumb == null || memo == null) return const SizedBox.shrink();
        return Positioned(
          left: 0,
          right: 0,
          // つまみの横棒の上端に、数字の上端をそろえる
          top: listTop + thumb.y - _thumbThickness / 2,
          child: AnimatedOpacity(
            opacity: _showsThumbDate.value ? 1 : 0,
            duration: _thumbDateFadeDuration,
            child: ListeningMemoDateBackdrop(dateTime: memo.createdAt),
          ),
        );
      },
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
          _buildThumbDate(
            memos: listening.memos,
            listTop: safeAreaTop + recordingSettingsPanelHeight,
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
          Positioned.fill(
            child: Listener(
              onPointerDown: (_) => _clearTextSelection(),
              child: const ListeningRecordingSettingsPanel(),
            ),
          ),
        ],
      ),
    );
  }
}
