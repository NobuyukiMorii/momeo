import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:momeo/database/app_database.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/pages/listening/memo_card_view_data.dart';
import 'package:momeo/providers/listening_providers.dart';
import 'package:momeo/widgets/listening_backdrop.dart';
import 'package:momeo/widgets/selection_action_button.dart';
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

  // 選択中のメモの id 一覧（選択中のカードは枠線が太くなる）
  final Set<int> _selectedMemoIds = {};

  // アクティブカード（リスニング中インジケーター）の出入りを司る
  //   forward = スライドダウンで登場、reverse = スライドアウトで退場、
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

    // 発話開始 → スライドダウンで登場
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

    // 空の認識結果（咳・物音の誤検知）→ 上へスライドアウト
    if (before != null &&
        after.emptyResultCount > before.emptyResultCount &&
        !after.speechActive) {
      _activeCardController.reverse();
    }
  }

  // ---------------------------------
  // アクティブカード（リスニング中インジケーター）
  // ---------------------------------
  // 発話中だけ上からスライドダウンして現れる。完全に隠れている間は
  // 中身ごとツリーから外し、ドット増減のタイマーも止めて常時負荷を避ける
  Widget _buildActiveCard() {
    return AnimatedBuilder(
      animation: _activeCardController,
      builder: (context, _) {
        if (_activeCardController.isDismissed) {
          return const SizedBox.shrink();
        }
        return SizeTransition(
          sizeFactor: _activeCardAnimation,
          axisAlignment: -1,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -1),
              end: Offset.zero,
            ).animate(_activeCardAnimation),
            child: const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.xl),
              child: VoiceCard(text: '', isListening: true),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------
  // カードの選択
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
  // 選択中メモの連結コピー
  // ---------------------------------
  void _copySelectedMemos(List<VoiceMemo> memos) {
    // memos は新しい順なので、逆順に走査して時系列順に組み立てる
    final selectedTexts = [
      for (final memo in memos.reversed)
        if (_selectedMemoIds.contains(memo.id)) memo.content,
    ];
    if (selectedTexts.isEmpty) return;
    // クリップボードにコピー
    Clipboard.setData(ClipboardData(text: selectedTexts.join('\n')));
    // 選択中のメモをクリア
    setState(() => _selectedMemoIds.clear());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(listeningProvider, _onListeningChanged);

    // 読み込み中・エラー時は空の一覧として扱う（この画面のエラーUIはまだ無い）
    final listening =
        ref.watch(listeningProvider).value ?? const ListeningState();
    final cards = buildMemoCardViewData(listening.memos);

    // 安全領域（ステータスバー・ホームインジケーター）は SafeArea で切り取らず、
    // スクロールの内側余白として足す。カードがシステム表示の下へ透けて
    // 滑り込みつつ、端までスクロールすれば全体が見えるようにする
    final safeArea = MediaQuery.paddingOf(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // 背景レイヤー：常時マイク音量に連動する縦棒メーター（カードの隙間から覗く）
          Positioned.fill(
            child: ListeningBackdrop(
              levelReader: () =>
                  ref.read(listeningProvider.notifier).latestLevel,
            ),
          ),
          // 前景：メモ一覧（透明なので背景のメーターが隙間から覗く）
          ListView.separated(
            padding: EdgeInsets.only(
              left: AppSpacing.l,
              right: AppSpacing.l,
              top: AppSpacing.xl + safeArea.top,
              bottom: AppSpacing.xl + safeArea.bottom,
            ),
            // 先頭のアクティブカード + 確定済みメモ
            itemCount: cards.length + 1,
            // アクティブカードの直後の間隔はカード側が持つ（非表示時に余白を残さないため）
            separatorBuilder: (_, index) =>
                SizedBox(height: index == 0 ? 0 : AppSpacing.xl),
            itemBuilder: (context, index) {
              // 先頭はアクティブカード
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
          // 右下のコピーボタン（選択中のカードがある間だけ現れる。
          // 出入り・タップ反応の演出はボタン側が持つ）
          Positioned(
            right: AppSpacing.l,
            bottom: AppSpacing.l + safeArea.bottom,
            child: SelectionActionButton(
              visible: _selectedMemoIds.isNotEmpty,
              icon: Icons.copy,
              onPressed: () => _copySelectedMemos(listening.memos),
            ),
          ),
        ],
      ),
    );
  }
}
