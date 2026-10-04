import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/database/app_database.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/providers/listening_providers.dart';
import 'package:momeo/widgets/listening_backdrop.dart';
import 'package:momeo/widgets/listening_memo_date_backdrop.dart';
import 'package:momeo/widgets/listening_recording_settings_panel.dart';
import 'package:momeo/widgets/native_memo_list.dart';

// スクロールが止まってから、つまみの横の日付を消し始めるまでの時間
const _thumbDateHideDelay = Duration(milliseconds: 600);

// つまみの横の日付が現れる・消える時間
const _thumbDateFadeDuration = Duration(milliseconds: 200);

// スクロールつまみの横棒の太さ（ネイティブ側の描画とそろえる）
const _thumbThickness = 0.5;

// =====================================================================
// リスニング画面
// =====================================================================
class ListeningPage extends ConsumerStatefulWidget {
  const ListeningPage({super.key});

  @override
  ConsumerState<ListeningPage> createState() => _ListeningPageState();
}

class _ListeningPageState extends ConsumerState<ListeningPage> {
  // ---------------------------------
  // 文字選択に関する状態
  // ---------------------------------
  // 文字選択は OS 側（ネイティブの一覧）が持つ
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

  @override
  void dispose() {
    _nativeMemoListController.dispose();
    _thumb.dispose();
    _thumbDateHideTimer?.cancel();
    _showsThumbDate.dispose();
    super.dispose();
  }

  // ---------------------------------
  // メモ一覧
  // ---------------------------------
  Widget _buildMemoList({
    required ListeningState listening,
    required double safeAreaTop,
    required double recordingSettingsPanelHeight,
  }) {
    return Padding(
      // 上端は、録音設定パネルの状態行のぶん空ける。下端は画面の下端まで広げる。
      // 録音設定パネルを開いても覆いかぶさるだけなので、ここは動かさない
      padding: EdgeInsets.only(top: safeAreaTop + recordingSettingsPanelHeight),
      child: NativeMemoList(
        memos: listening.memos,
        controller: _nativeMemoListController,
        typingMemoId: listening.typeInMemoId,
        typeFrom: listening.typeInFrom,
        speakingDots: _speakingDots(listening),
        onThumbChanged: _onThumbChanged,
        onDeleteText: _onDeleteText,
        onTypingComplete: _onTypingComplete,
      ),
    );
  }

  // 文字選択のメニューで「削除」が押されたら、選んだ範囲の文字をメモから消す
  void _onDeleteText(List<MemoTextRange> ranges) {
    unawaited(ref.read(listeningProvider.notifier).deleteTextRanges(ranges));
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
    // 安全領域
    // ---------------------------------
    final safeAreaTop = MediaQuery.paddingOf(context).top;

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
          // スクロール中だけ、つまみの横の背景に出す日付
          // ---------------------------------
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
          ),
          // ---------------------------------
          // 録音設定パネル
          // ---------------------------------
          // 触れたら、本文の文字選択を外す
          Positioned.fill(
            child: Listener(
              onPointerDown: (_) => _nativeMemoListController.clearSelection(),
              child: const ListeningRecordingSettingsPanel(),
            ),
          ),
        ],
      ),
    );
  }
}
