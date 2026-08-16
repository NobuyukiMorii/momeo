import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/pages/listening/memo_card_view_data.dart';
import 'package:momeo/pages/listening/memo_keyword_filter.dart';
import 'package:momeo/providers/listening_providers.dart';
import 'package:momeo/widgets/listening_backdrop.dart';
import 'package:momeo/widgets/listening_header.dart';
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {

  // ---------------------------------
  // 選択中のメモに関する状態
  // ---------------------------------
  // 日時フォーマット
  static final _dateFormat = DateFormat('y/M/d HH:mm');
  // 選択中のメモの id
  final Set<int> _selectedMemoIds = {};

  // ---------------------------------
  // 検索フィールドに関する状態
  // ---------------------------------
  // 検索フィールドに打たれている文字列
  final TextEditingController _keywordController = TextEditingController();
  // 検索フィールドにカーソルが当たっているか
  final FocusNode _keywordFocusNode = FocusNode();
  // 検索フィールドに入力されたキーワード
  List<String> _keywords = const [];
  // 検索フィールドに入力中か（入力に入った時点で下端のシートを畳む）
  bool _isKeywordInputActive = false;
  // 前回このイベントが届いた時、キーボードが出ていたか
  bool _wasKeyboardOpen = false;

  // ---------------------------------
  // 下端のシートに関する状態
  // ---------------------------------
  // 下端のシートの高さ
  final ValueNotifier<double> _sheetHeight = ValueNotifier(0);

  // ---------------------------------
  // コピーの知らせに関する状態
  // ---------------------------------
  // コピーの知らせを出すカードの id
  int? _copiedMemoId;
  // コピーの知らせのタイマー
  Timer? _copyNoticeTimer;

  // ---------------------------------
  // アクティブカードに関する状態
  // ---------------------------------
  // 出入りの進み具合（0 = 隠れきっている、1 = 出きっている）
  late final AnimationController _activeCardController;
  // 進み具合に緩急を付けた値（カードの高さに使う）
  late final CurvedAnimation _activeCardAnimation;

  @override
  void initState() {
    super.initState();
    // キーボードが閉じた瞬間を検知
    WidgetsBinding.instance.addObserver(this);
    // 検索フィールドのフォーカスの通知を受け取る
    _keywordFocusNode.addListener(_onKeywordFocusChanged);
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
    WidgetsBinding.instance.removeObserver(this);
    _copyNoticeTimer?.cancel(); // コピーの知らせのタイマーを止める
    _keywordController.dispose(); // 検索フィールドのコントローラーを破棄
    _keywordFocusNode.removeListener(_onKeywordFocusChanged); // 検索フィールドのフォーカスの通知を受け取らないようにする
    _keywordFocusNode.dispose(); // 検索フィールドのフォーカスノードを破棄
    _sheetHeight.dispose();
    _activeCardAnimation.dispose();
    _activeCardController.dispose();
    super.dispose();
  }

  // ---------------------------------
  // Flutterのウィジェットツリーの寸法が変わったときに呼ばれる
  // ---------------------------------
  @override
  void didChangeMetrics() {

    // ---------------------------------
    // キーボードが閉じた瞬間を検知
    // ---------------------------------

    // --- マウントされていない場合は何もしない
    if (!mounted) return;
    // --- 今キーボードが開いているか
    final isOpen = View.of(context).viewInsets.bottom > 0;
    // --- 前回と同じなら、キーボード開閉は起きていない
    if (isOpen == _wasKeyboardOpen) return;
    // --- 次のキーボード開閉で比較するために値を記録
    _wasKeyboardOpen = isOpen;
    if (!isOpen) { // --- キーボードを閉じた
      _exitKeywordInput(); // 検索フィールドからカーソルを外す
    }
  }

  // ---------------------------------
  // 検索フィールドのキーワードを反映
  // ---------------------------------
  void _applyKeywords() {
    // --- 入力文字列を、照合に使う語の一覧へ分解
    setState(() => _keywords = parseMemoKeywords(_keywordController.text));
  }

  // ---------------------------------
  // 検索フィールドにカーソルが当たった・外れたとき
  // ---------------------------------
  void _onKeywordFocusChanged() {
    // --- 今カーソルが当たっているか
    final isActive = _keywordFocusNode.hasFocus;
    // --- カーソルが当たっているまま、またカーソルが当たっている
    if (isActive == _isKeywordInputActive) return; // 何もしない
    // --- カーソルが当たっている間は下端のシートを畳んでおく
    setState(() => _isKeywordInputActive = isActive);
    // --- カーソルが外れたら文字列を絞り込みへ取り込む
    if (!isActive) _applyKeywords();
  }

  // ---------------------------------
  // 検索フィールドからカーソルを外す
  // ---------------------------------
  void _exitKeywordInput() {
    // --- すでにカーソルが外れていれば何もしない
    if (!_keywordFocusNode.hasFocus) return;
    // --- カーソルを外す
    _keywordFocusNode.unfocus();
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
  // カード長押しでコピー
  // ---------------------------------
  void _copyMemo(int memoId, String text) {
    // 知らせを出しておく時間
    const noticeDuration = Duration(milliseconds: 3600);
    // --- クリップボードにコピー
    Clipboard.setData(ClipboardData(text: text));
    // --- カード左上に通知を表示
    setState(() => _copiedMemoId = memoId);
    // --- 続けてコピーした場合、最後の通知を非表示とする
    _copyNoticeTimer?.cancel();
    // --- 通知を一定時間表示
    _copyNoticeTimer = Timer(noticeDuration, () {
      if (mounted) setState(() => _copiedMemoId = null);
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

  // ---------------------------------
  // 絞り込みで隠れたカードのタイピング演出を取り消す
  // ---------------------------------
  void _cancelHiddenTypeIn(int? typeInMemoId, List<MemoCardViewData> cards) {
    // --- 演出の対象がいない
    if (typeInMemoId == null) return;
    // --- 対象が一覧に出ている。演出が終わったらカード自身が知らせる
    if (cards.any((card) => card.memo.id == typeInMemoId)) return;

    // --- カードの代わりに終わったと知らせる
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // --- 待つ間に画面を離れていたら何もしない
      if (!mounted) return;
      // --- Notifier に終わったと知らせる
      ref.read(listeningProvider.notifier).onTypingComplete(typeInMemoId);
    });
  }

  // ---------------------------------
  // 確定済みメモカード1枚
  // ---------------------------------
  Widget _buildMemoCard(MemoCardViewData card, int? typeInMemoId) {
    return VoiceCard(
      key: ValueKey(card.memo.id),
      text: card.memo.content,
      dateTime:
          card.showDateTime ? _dateFormat.format(card.memo.createdAt) : null,
      typeIn: card.memo.id == typeInMemoId,
      selected: _selectedMemoIds.contains(card.memo.id),
      onTap: () => _toggleMemoSelection(card.memo.id),
      onLongPress: () => _copyMemo(card.memo.id, card.memo.content),
      showCopyNotice: _copiedMemoId == card.memo.id,
      // 演出が終わったと Notifier に返す（スクロールで戻っても再生し直さない）
      onTypingComplete: () {
        if (!mounted) return;
        ref.read(listeningProvider.notifier).onTypingComplete(card.memo.id);
      },
    );
  }

  // ---------------------------------
  // ボイスカード一覧
  // ---------------------------------
  Widget _buildMemoList({
    required List<MemoCardViewData> cards,
    required int? typeInMemoId,
    required bool isFiltering,
    required double safeAreaTop,
    required double safeAreaBottom,
  }) {
    // --- シートの高さが動くたびに、下端余白を追従させる
    return ValueListenableBuilder<double>(
      valueListenable: _sheetHeight,
      builder: (context, sheetHeight, _) => ListView.separated(
        // --- 新しいカードが下に来るよう、下から積む
        reverse: true,
        padding: EdgeInsets.only(
          left: AppSpacing.l,
          right: AppSpacing.l,
          top: AppSpacing.xl + safeAreaTop + listeningHeaderHeight,
          // キーボードの有無で余白を変えない（一覧を動かさない）
          bottom: AppSpacing.xl + safeAreaBottom + sheetHeight,
        ),
        // --- 確定済みメモ + 一番下のアクティブカードで1つ多い
        itemCount: cards.length + 1,
        // --- アクティブカードとの間隔はカード側が持つ（消えた時に余白を残さない）
        separatorBuilder: (_, index) =>
            SizedBox(height: index == 0 ? 0 : AppSpacing.xl),
        itemBuilder: (context, index) {
          if (index == 0) { // --- 一番下はアクティブカード
            // --- 検索中ならアクティブカードを出さず、一覧を検索結果に徹させる
            return isFiltering ? const SizedBox.shrink() : _buildActiveCard();
          }
          return _buildMemoCard(cards[index - 1], typeInMemoId);
        },
      ),
    );
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
    // キーワードによる絞り込み（いずれかの語を含むメモだけ残る）
    // ---------------------------------
    final isFiltering = _keywords.isNotEmpty;
    final visibleMemos = filterMemosByKeywords(listening.memos, _keywords);

    // ---------------------------------
    // ボイスカード一覧（日時の出し分けは絞り込んだ後の並びで決める）
    // ---------------------------------
    final cards = buildMemoCardViewData(visibleMemos);
    _cancelHiddenTypeIn(listening.typeInMemoId, cards);

    // ---------------------------------
    // 選択中のメモ（memos は新しい順なので、時系列順に並べ替える）
    //   絞り込みで隠れているメモも選択は保つので、絞り込む前の一覧から拾う
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

    return Scaffold(
      backgroundColor: AppColors.surface,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _exitKeywordInput(),
              child: Stack(
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
                  _buildMemoList(
                    cards: cards,
                    typeInMemoId: listening.typeInMemoId,
                    isFiltering: isFiltering,
                    safeAreaTop: safeAreaTop,
                    safeAreaBottom: safeAreaBottom,
                  ),
                  // ---------------------------------
                  // 下端のシート（ブラックボードと録音の設定）
                  // ---------------------------------
                  Positioned.fill(
                    child: ListeningInsetSheet(
                      heightNotifier: _sheetHeight,
                      isCollapsed: _isKeywordInputActive,
                      selectedMemos: selectedMemos,
                      onClearSelection: _clearMemoSelection,
                      onDeleteSelection: _deleteSelectedMemos,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ---------------------------------
          // ヘッダー
          // ---------------------------------
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ListeningHeader(
              controller: _keywordController,
              focusNode: _keywordFocusNode,
              onCleared: _applyKeywords,
            ),
          ),
        ],
      ),
    );
  }
}
