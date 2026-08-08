import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/pages/listening/memo_card_view_data.dart';
import 'package:momeo/providers/listening_providers.dart';
import 'package:momeo/widgets/listening_backdrop.dart';
import 'package:momeo/widgets/listening_inset_sheet.dart';
import 'package:momeo/widgets/voice_card.dart';

// =====================================================================
// ListeningPage — リスニング画面
//
//   状態（メモ一覧・発話中かどうか・演出の対象）は listeningProvider が
//   一元管理する。この画面は watch して描画し、状態の変化をアクティブ
//   カードのアニメーションに翻訳するだけの View に徹する。
// =====================================================================
class ListeningPage extends ConsumerStatefulWidget {
  const ListeningPage({super.key});

  @override
  ConsumerState<ListeningPage> createState() => _ListeningPageState();
}

class _ListeningPageState extends ConsumerState<ListeningPage>
    with SingleTickerProviderStateMixin {
  // 表示用日時フォーマット（生成コストを抑えて使い回す）
  static final _dateFormat = DateFormat('y/M/d HH:mm');

  // 選択中のメモの id（そのままコピー・削除の対象になる）
  final Set<int> _selectedMemoIds = {};

  // 下端のシートが今取っている高さ（一覧の下端余白として使い、カードを押し上げる）
  final ValueNotifier<double> _sheetHeight = ValueNotifier(0);

  // アクティブカード（リスニング中インジケーター）の出入りを司る
  //   forward = せり上がって登場、reverse = 沈み込んで退場、
  //   value に 0.0 を代入 = 即時に消す（確定メモへの置き換え＝モーフ用）
  late final AnimationController _activeCardController;
  late final CurvedAnimation _activeCardAnimation;

  @override
  void initState() {
    super.initState();
    _activeCardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _activeCardAnimation = CurvedAnimation(
      parent: _activeCardController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _sheetHeight.dispose();
    _activeCardAnimation.dispose();
    _activeCardController.dispose();
    super.dispose();
  }

  // ---------------------------------
  // 状態の変化をアクティブカードのアニメーションに翻訳する
  // ---------------------------------
  void _onListeningChanged(
    AsyncValue<ListeningState>? previous,
    AsyncValue<ListeningState> next,
  ) {
    final before = previous?.value;
    final after = next.value;
    if (after == null) return;

    // 発話開始 → スライドアップで登場
    final wasActive = before?.speechActive ?? false;
    if (after.speechActive && !wasActive) {
      _activeCardController.forward();
    }

    // メモ確定（先頭の id が変わった）→ 即時に消し、同じ位置に確定カードを
    // 見せる（ドットが文字に置き換わったように見えるモーフ）。まだ発話が
    // 続いていれば（30秒上限の強制区切り）、新しいカードを出し直す
    final firstIdBefore = before?.memos.firstOrNull?.id;
    final firstIdAfter = after.memos.firstOrNull?.id;
    if (firstIdAfter != null && firstIdAfter != firstIdBefore) {
      _activeCardController.value = 0.0;
      if (after.speechActive) _activeCardController.forward();
    }

    // 空の認識結果（咳・物音の誤検知）→ 下へスライドアウト
    if (before != null &&
        after.emptyResultCount > before.emptyResultCount &&
        !after.speechActive) {
      _activeCardController.reverse();
    }
  }

  // ---------------------------------
  // アクティブカード（リスニング中インジケーター）
  // ---------------------------------
  // 発話中だけ下から滑り込んで現れる。完全に隠れている間は
  // 中身ごとツリーから外し、ドット増減のタイマーも止めて常時負荷を避ける
  Widget _buildActiveCard() {
    return AnimatedBuilder(
      animation: _activeCardController,
      builder: (context, _) {
        if (_activeCardController.isDismissed) {
          return const SizedBox.shrink();
        }
        // 一覧に占める高さが上のカードを押し上げる量になるので、カード自身は
        // その箱の上辺に貼り付けて下へはみ出させ、押し上げと同じ速さで昇らせる。
        // クリップしないので、はみ出した下辺は画面の外に隠れるだけで切れない
        return Align(
          alignment: Alignment.topCenter,
          heightFactor: _activeCardAnimation.value,
          child: const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xl),
            child: VoiceCard(text: '', isListening: true),
          ),
        );
      },
    );
  }

  // ---------------------------------
  // カードの選択・非選択
  // ---------------------------------
  void _toggleMemoSelection(int memoId) {
    setState(() {
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
    setState(_selectedMemoIds.clear);
  }

  // ---------------------------------
  // 選択中のメモを削除する（DB からも消える。元に戻す手段は無い）
  // ---------------------------------
  Future<void> _deleteSelectedMemos() async {
    final targetIds = Set<int>.from(_selectedMemoIds);
    await ref.read(listeningProvider.notifier).deleteMemos(targetIds);
    if (!mounted) return;
    setState(() => _selectedMemoIds.removeAll(targetIds));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(listeningProvider, _onListeningChanged);

    // ---------------------------------
    // リスニング状態
    // ---------------------------------
    final listening =
        ref.watch(listeningProvider).value ?? const ListeningState();

    // ---------------------------------
    // ボイスカード一覧
    // ---------------------------------
    final cards = buildMemoCardViewData(listening.memos);

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
    final safeArea = MediaQuery.paddingOf(context);

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
          // ボイスカード一覧
          // ---------------------------------
          ValueListenableBuilder<double>(
            valueListenable: _sheetHeight,
            builder: (context, sheetHeight, _) => ListView.separated(
              reverse: true,
              padding: EdgeInsets.only(
                left: AppSpacing.l,
                right: AppSpacing.l,
                top: AppSpacing.xl + safeArea.top,
                bottom: AppSpacing.xl + safeArea.bottom + sheetHeight,
              ),
              // 下端のアクティブカード + 確定済みメモ（新しい順 = 下から順）
              itemCount: cards.length + 1,
              // アクティブカードとの間隔はカード側が持つ（非表示時に余白を残さないため）
              separatorBuilder: (_, index) =>
                  SizedBox(height: index == 0 ? 0 : AppSpacing.xl),
              itemBuilder: (context, index) {
                // 一番下はアクティブカード
                if (index == 0) return _buildActiveCard();

                // 確定済みメモカード（直前に確定した1件だけタイピング演出）
                final card = cards[index - 1];
                return VoiceCard(
                  key: ValueKey(card.memo.id),
                  text: card.memo.content,
                  dateTime: card.showDateTime
                      ? _dateFormat.format(card.memo.createdAt)
                      : null,
                  typeIn: card.memo.id == listening.typeInMemoId,
                  selected: _selectedMemoIds.contains(card.memo.id),
                  onTap: () => _toggleMemoSelection(card.memo.id),
                  // 演出を使い切ったら Notifier に返して再再生を防ぐ
                  onTypingComplete: () {
                    if (!mounted) return;
                    ref
                        .read(listeningProvider.notifier)
                        .onTypingComplete(card.memo.id);
                  },
                );
              },
            ),
          ),
          // ---------------------------------
          // 設定シート
          // ---------------------------------
          Positioned.fill(
            child: ListeningInsetSheet(
              heightNotifier: _sheetHeight,
              selectedMemos: selectedMemos,
              onClearSelection: _clearMemoSelection,
              onDeleteSelection: _deleteSelectedMemos,
            ),
          ),
        ],
      ),
    );
  }
}
