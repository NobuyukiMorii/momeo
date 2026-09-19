import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:momeo/database/app_database.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/pages/listening/memo_card_view_data.dart';
import 'package:momeo/pages/listening/memo_keyword_filter.dart';
import 'package:momeo/providers/listening_providers.dart';
import 'package:momeo/widgets/date_separator.dart';
import 'package:momeo/widgets/listening_backdrop.dart';
import 'package:momeo/widgets/listening_recording_settings_panel.dart';
import 'package:momeo/widgets/listening_search_field.dart';
import 'package:momeo/widgets/listening_selection_bar.dart';
import 'package:momeo/widgets/voice_card.dart';

// 日付区切りと上下のカードとの間隔（カード同士の間隔より広く取る）
const _dateSeparatorSpacing = AppSpacing.xxl;

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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ---------------------------------
  // 選択中のメモに関する状態
  // ---------------------------------
  // 時刻フォーマット（日付はカードの上の区切りが持つ）
  static final _timeFormat = DateFormat('HH:mm');
  // 選択中のメモの id（検索で一覧から隠れても外さない）
  final Set<int> _selectedMemoIds = {};

  // ---------------------------------
  // 検索フィールドに関する状態
  // ---------------------------------
  // 検索フィールドに打たれている文字列
  final TextEditingController _keywordController = TextEditingController();
  // 検索フィールドにカーソルが当たっているか
  final FocusNode _keywordFocusNode = FocusNode();
  // 一覧の絞り込みに使う語（カーソルが外れた時点の文字列から作る）
  List<String> _keywords = const [];
  // 前回このイベントが届いた時、キーボードが出ていたか
  bool _wasKeyboardOpen = false;

  // ---------------------------------
  // 選択バーに関する状態
  // ---------------------------------
  // 出具合（0 = 隠れきっている、1 = 出きっている）。バー自身と一覧の押し上げで共有する
  late final AnimationController _selectionBarController;

  // ---------------------------------
  // コピーの知らせに関する状態
  // ---------------------------------
  // コピーの知らせを出すカードの id
  int? _copiedMemoId;
  // コピーの知らせのタイマー
  Timer? _copyNoticeTimer;
  // 選択バーに出している一言（null なら出していない）
  String? _selectionBarNotice;
  // 選択バーの一言を引っ込めるタイマー
  Timer? _selectionBarNoticeTimer;

  // ---------------------------------
  // アクティブカードに関する状態
  // ---------------------------------
  // 出入りの進み具合（0 = 隠れきっている、1 = 出きっている）
  late final AnimationController _activeCardController;
  // 進み具合に緩急を付けた値（カードの高さに使う）
  late final CurvedAnimation _activeCardAnimation;
  // アクティブカードに出す時刻
  DateTime? _activeCardTime;

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
    _activeCardController.addStatusListener(_onActiveCardStatusChanged);
    _activeCardAnimation = CurvedAnimation(
      parent: _activeCardController,
      curve: Curves.easeOut,
    );
    _selectionBarController = AnimationController(
      vsync: this,
      duration: _selectionBarSlideDuration,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _copyNoticeTimer?.cancel(); // コピーの知らせのタイマーを止める
    _selectionBarNoticeTimer?.cancel(); // 選択バーの一言のタイマーを止める
    _keywordController.dispose(); // 検索フィールドのコントローラーを破棄
    _keywordFocusNode.removeListener(
      _onKeywordFocusChanged,
    ); // 検索フィールドのフォーカスの通知を受け取らないようにする
    _keywordFocusNode.dispose(); // 検索フィールドのフォーカスノードを破棄
    _selectionBarController.dispose();
    _activeCardAnimation.dispose();
    _activeCardController.removeStatusListener(_onActiveCardStatusChanged);
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
    if (!isOpen) {
      // --- キーボードを閉じた
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
    // --- 入力中は絞り込みを変えない
    if (_keywordFocusNode.hasFocus) return;
    // --- カーソルが外れたら文字列を絞り込みへ取り込む
    _applyKeywords();
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
  // アクティブカードのアニメーションが終わったとき
  // ---------------------------------
  void _onActiveCardStatusChanged(AnimationStatus status) {
    // --- アニメーションが終わっていなければ何もしない
    if (status != AnimationStatus.dismissed) return;
    // --- 画面がマウントされていない、またはアクティブカードの時刻がなければ何もしない
    if (!mounted || _activeCardTime == null) return;
    // --- アクティブカードの時刻を null にする
    setState(() => _activeCardTime = null);
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
      setState(() => _activeCardTime = after.speechStartedAt); // 時刻を記録
    }

    // メモ確定（先頭の id が変わった）→ 即時に消し、同じ位置に確定カードを
    // 見せる（ドットが文字に置き換わったように見えるモーフ）。まだ発話が
    // 続いていれば（30秒上限の強制区切り）、新しいカードを出し直す
    final firstIdBefore = before?.memos.firstOrNull?.id;
    final firstIdAfter = after.memos.firstOrNull?.id;
    if (firstIdAfter != null && firstIdAfter != firstIdBefore) {
      _activeCardController.value = 0.0;
      if (after.speechActive) { // 発話中なら
        _activeCardController.forward(); // アクティブカードが下から滑り込んで現れる/下へ引っ込むアニメーションを進める
        setState(() => _activeCardTime = after.speechStartedAt); // 時刻を記録
      }
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
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: VoiceCard(
              text: '',
              isListening: true,
              dateTime: _activeCardTime == null
                  ? null
                  : _timeFormat.format(_activeCardTime!),
            ),
          ),
        );
      },
    );
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
  // カードの選択・非選択
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
  // カード長押しでコピー
  // ---------------------------------
  void _copyMemo(int memoId, String text) {
    // --- クリップボードにコピー
    Clipboard.setData(ClipboardData(text: text));
    // --- カード左上に通知を表示
    setState(() => _copiedMemoId = memoId);
    // --- 続けてコピーした場合、最後の通知を非表示とする
    _copyNoticeTimer?.cancel();
    // --- 通知を一定時間表示
    _copyNoticeTimer = Timer(_noticeDuration, () {
      if (mounted) setState(() => _copiedMemoId = null);
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
    final voiceCard = VoiceCard(
      key: ValueKey(card.memo.id),
      text: card.memo.content,
      dateTime: card.showDateTime
          ? _timeFormat.format(card.memo.createdAt)
          : null,
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

    // --- 日付が変わる境目では、カードの上へ区切りを挟む
    return Column(
      children: [
        if (card.dateSeparatorLabel != null) ...[
          const SizedBox(height: _dateSeparatorSpacing - AppSpacing.xl),
          DateSeparator(label: card.dateSeparatorLabel!),
          const SizedBox(height: _dateSeparatorSpacing),
        ],
        voiceCard,
      ],
    );
  }

  // ---------------------------------
  // ボイスカード一覧
  // ---------------------------------
  Widget _buildMemoList({
    required List<MemoCardViewData> cards,
    required int? typeInMemoId,
    required bool hidesActiveCard,
    required double safeAreaTop,
    required double recordingSettingsPanelHeight,
    required double safeAreaBottom,
  }) {
    // ---------------------------------
    // 並べるカード
    // ---------------------------------
    final memoCards = SliverList.separated(
      // --- 確定済みメモ + 一番下のアクティブカードで1つ多い
      itemCount: cards.length + 1,
      // --- アクティブカードとの間隔はカード側が持つ（消えた時に余白を残さない）
      separatorBuilder: (_, index) =>
          SizedBox(height: index == 0 ? 0 : AppSpacing.xl),
      itemBuilder: (context, index) {
        if (index == 0) {
          // --- 一番下はアクティブカード（出すかは呼び出し側が決める）
          return hidesActiveCard ? const SizedBox.shrink() : _buildActiveCard();
        }
        return _buildMemoCard(cards[index - 1], typeInMemoId);
      },
    );

    // ---------------------------------
    // 余白を付けて下から積む
    // ---------------------------------
    return AnimatedBuilder(
      animation: _selectionBarController,
      child: memoCards,
      builder: (context, memoCards) => CustomScrollView(
        // --- 新しいカードが下に来るよう、下から積む
        reverse: true,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(
              left: AppSpacing.xs,
              right: AppSpacing.xs,
              // 上端は、録音設定パネルの状態行と検索フィールドのぶん空ける。
              // 録音設定パネルを開いても覆いかぶさるだけなので、ここは動かさない
              top:
                  AppSpacing.xl +
                  safeAreaTop +
                  recordingSettingsPanelHeight +
                  listeningSearchFieldHeight,
              // キーボードの有無で余白を変えない（一覧を動かさない）
              // 下端は、選択バーの出入りと同じ動きで押し上げる
              bottom:
                  AppSpacing.xl +
                  safeAreaBottom +
                  listeningSelectionBarPushUpHeight(
                    slideProgress: _selectionBarController.value,
                    safeAreaBottom: safeAreaBottom,
                  ),
            ),
            sliver: memoCards,
          ),
        ],
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
    // 検索フィールドの語で絞り込んだメモ
    // ---------------------------------
    final visibleMemos = filterMemosByKeywords(listening.memos, _keywords);

    // ---------------------------------
    // アクティブカード（発話中のカード）
    // ---------------------------------
    final hidesActiveCard = _keywords.isNotEmpty;

    // ---------------------------------
    // ボイスカード一覧（日時の出し分けは絞り込んだ後の並びで決める）
    // ---------------------------------
    final cards = buildMemoCardViewData(
      visibleMemos,
      today: DateTime.now(),
      // 絞り込み中はアクティブカードを出さないので、時刻を譲る相手もいない
      activeCardTime: hidesActiveCard ? null : _activeCardTime,
    );
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

    // ---------------------------------
    // 録音設定パネルが閉じているときの高さ
    // ---------------------------------
    final recordingSettingsPanelHeight =
        listeningRecordingSettingsPanelCollapsedHeightOf(context);

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
                    hidesActiveCard: hidesActiveCard,
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
                ],
              ),
            ),
          ),
          // ---------------------------------
          // 検索フィールド
          // ---------------------------------
          Positioned(
            top: safeAreaTop + recordingSettingsPanelHeight,
            left: 0,
            right: 0,
            child: ListeningSearchField(
              controller: _keywordController,
              focusNode: _keywordFocusNode,
              onCleared: _applyKeywords,
            ),
          ),
          // ---------------------------------
          // 録音設定パネル
          // ---------------------------------
          Positioned.fill(
            child: Listener(
              onPointerDown: (_) => _exitKeywordInput(),
              child: const ListeningRecordingSettingsPanel(),
            ),
          ),
        ],
      ),
    );
  }
}
