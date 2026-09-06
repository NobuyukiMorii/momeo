import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_radius.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/models/listening_sheet_tab.dart';
import 'package:momeo/providers/settings_providers.dart';
import 'package:momeo/widgets/background_recording_disclosure_dialog.dart';
import 'package:momeo/widgets/dot.dart';
import 'package:momeo/widgets/pressable_scale.dart';
import 'package:permission_handler/permission_handler.dart';

// ============================================================
// 画面下端の領域を上下のスワイプで広げ縮めするシート
//
//   帯にタブが並んでいて、常にどれかを選んでいる。
//   「どのタブを選んでいるか」と「シートを開いているか」は別の状態で、
//   どちらも画面側（ListeningPage）が持つ。このシートは受け取った状態を
//   高さに翻訳して描く。閉じても選んでいたタブはそのまま残る。
//
//   操作のタブは 1 件も選んでいなくても出し、中の操作を押せない見た目にする。
//   タブが出たり消えたりすると、帯の並びが変わって押し間違いを招くため。
//   タブは長押しして左右へ動かすと並び替えられ、その順序は端末に保存する。
// ============================================================

// ---------------------------------
// 定数: 高さ
// ---------------------------------

// タブの帯の高さ（閉じているときはこの帯だけが見えている）
const _bandHeight = 52.0;

// 帯の下に出すカード群の高さ（背の高い録音の選択肢に合わせた固定値）
const _panelCardHeight = 172.0;

// カード群の上下の余白（上は帯との間、下は安全領域との間）
const _panelPaddingTop = AppSpacing.s;
const _panelPaddingBottom = AppSpacing.l;

// 開き切ったときの高さ（帯 + 余白 + カード群）
const _openHeight =
    _bandHeight + _panelPaddingTop + _panelCardHeight + _panelPaddingBottom;

// ドラッグの移動量を開き具合の割合へ換算する分母
const _dragRange = _openHeight - _bandHeight;

// ---------------------------------
// 定数: 見た目
// ---------------------------------

// 下線と、選んでいるタブの枠線の太さ（選択中のボイスカードの太い枠線に揃える）
const _tabStrokeWidth = 3.0;

// 選んでいないタブの枠線の太さ（選択していないボイスカードの細い枠線に揃える）
const _inactiveTabStrokeWidth = 1.5;

// 選んでいるタブの上の角の丸み
const _tabCornerRadius = AppRadius.l;

// 選んでいないタブの枠を、上端からさらに下げて描く量（面の奥へ沈んで見せる）
const _inactiveTabDepth = 3.0;

// 押せない操作の薄さ
const _disabledOpacity = 0.35;

// 録音の選択肢のドットの直径（選んでいる選択肢だけ少し大きくする）
const _optionDotSize = 8.0;
const _optionSelectedDotSize = 12.0;

// 帯に出す録音状態の文言の幅（状態が切り替わってもタブ幅を動かさない）
const _recordingStatusLabelWidth = 186.0;

// 並び替え中のタブを持ち上げる距離と拡大率
const _draggedTabLift = 4.0;
const _draggedTabScale = 1.02;

// タブの並び替えを始めるまで押し続ける時間（Flutter 標準は 500ms）
const _tabReorderLongPressDuration = Duration(milliseconds: 350);

// ---------------------------------
// 定数: 画面に出る文言
// ---------------------------------

// バックグラウンド録音の状態を伝える、帯の文言
const _statusLabelEnabled = 'ほかのアプリを使っていても録音';
const _statusLabelDisabled = 'このアプリを使ってる時だけ録音';

// バックグラウンド録音の選択肢（無効側・有効側）
const _optionTitleDisabled = 'このアプリを使ってる時だけ録音';
const _optionDescriptionDisabled = 'ほかのアプリを使っている間やホーム画面では録音を止め、このアプリに戻ると再開します。';
const _optionTitleEnabled = 'ほかのアプリを使っていても録音';
const _optionDescriptionEnabled = 'ほかのアプリを使っている間やホーム画面でも録音し続けます。';

// 選択中のメモへの操作（カードは削除・コピーの2枚、解除は右下のテキスト）
const _actionTitleDelete = '削除';
const _actionTitleCopy = 'コピー';
const _actionTitleClear = '解除';

// コピーカードの上に出す知らせの文言と大きさ
const _copyNoticeLabel = 'コピーしました';
const _copyNoticeFontSize = 10.0;

// 削除カードを押したときに出す確認ダイアログの文言
const _deleteDialogTitle = '選択中のメモを削除しますか？';
const _deleteDialogMessage = '一度削除すると復元できません。';
const _deleteDialogCancelLabel = 'キャンセル';
const _deleteDialogConfirmLabel = '削除する';

// ---------------------------------
// 定数: 文字列のフォーマット
// ---------------------------------

// 選択件数の3桁区切り（1000 件を超えることはまず無いが、桁が読める形にしておく）
final _selectionCountFormat = NumberFormat('#,###');

// ---------------------------------
// クラス本体
// ---------------------------------
class ListeningInsetSheet extends ConsumerStatefulWidget {
  const ListeningInsetSheet({
    super.key,
    required this.heightNotifier,
    required this.isForcedCollapsed,
    required this.tab,
    required this.isOpen,
    required this.onTabSelected,
    required this.onOpenChanged,
    required this.selectedCount,
    required this.onClearSelection,
    required this.onDeleteSelection,
    required this.onCopySelection,
    required this.isCopyNoticeVisible,
  });

  // 今のシートの高さ（安全領域を除いた、一覧を押し上げるぶん）
  final ValueNotifier<double> heightNotifier;

  // 画面側の都合で、アニメーションを挟まずその場で畳ませる
  final bool isForcedCollapsed;

  // 今選んでいるタブ
  final ListeningSheetTab tab;

  // シートを開いているか
  final bool isOpen;

  // タブをタップしたときの通知（選んでいるタブを押したときも届く）
  final ValueChanged<ListeningSheetTab> onTabSelected;

  // スワイプでシートを開き閉じしたときの通知
  final ValueChanged<bool> onOpenChanged;

  // 選択中のメモの件数
  final int selectedCount;

  // 解除ボタンをタップしたときに、選択をすべて解除する
  final VoidCallback onClearSelection;

  // 削除を確認したときに、選択中のメモを DB ごと消す
  final Future<void> Function() onDeleteSelection;

  // コピーカードをタップしたときに、選択中のメモをクリップボードに入れる
  final VoidCallback onCopySelection;

  // コピーした知らせを、コピーカードの上に出しているか
  final bool isCopyNoticeVisible;

  @override
  ConsumerState<ListeningInsetSheet> createState() =>
      _ListeningInsetSheetState();
}

// ---------------------------------
// 状態
// ---------------------------------
class _ListeningInsetSheetState extends ConsumerState<ListeningInsetSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _openController;

  // ---------------------------------
  // コントローラを用意し、高さの変化を外へ流す
  // ---------------------------------
  @override
  void initState() {
    // --- 親の初期化を先に済ませる
    super.initState();
    // --- 開き具合を動かすコントローラを用意する（開閉アニメーションの時間）
    _openController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    // --- 値が動くたびに、今の高さを外へ伝える
    _openController.addListener(_publishHeight);
  }

  // ---------------------------------
  // 画面側から届いた変化を開閉に翻訳する
  // ---------------------------------
  @override
  void didUpdateWidget(ListeningInsetSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // --- 検索フィールドの入力が始まったら、アニメーションを挟まずその場で閉じる
    if (widget.isForcedCollapsed && !oldWidget.isForcedCollapsed) {
      _collapseImmediately();
      return;
    }
    // --- 開き閉じが変わっていなければ何もしない
    if (widget.isOpen == oldWidget.isOpen) return;
    // --- 画面側の状態に合わせて動かす
    widget.isOpen ? _openController.forward() : _openController.reverse();
  }

  // ---------------------------------
  // その場でシートを畳む
  // ---------------------------------
  void _collapseImmediately() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openController.value = 0;
    });
  }

  // ---------------------------------
  // 後片付け
  // ---------------------------------
  @override
  void dispose() {
    // --- 高さの通知を止める
    _openController.removeListener(_publishHeight);
    // --- コントローラを破棄する
    _openController.dispose();
    // --- 親の後片付けを最後に行う
    super.dispose();
  }

  // ---------------------------------
  // 今の高さ
  // ---------------------------------
  double get _currentHeight => _bandHeight + _dragRange * _openController.value;

  // ---------------------------------
  // 今の高さを画面側へ伝える
  // ---------------------------------
  void _publishHeight() {
    // --- 閉じた高さに開いたぶんを足した値を渡す
    widget.heightNotifier.value = _currentHeight;
  }

  // ---------------------------------
  // 開閉
  // ---------------------------------

  // スワイプで開き閉じしたとき（画面側の通知を待たず、ここでも動かして落ち着かせる）
  void _open() {
    _openController.forward();
    if (!widget.isOpen) widget.onOpenChanged(true);
  }

  void _close() {
    _openController.reverse();
    if (widget.isOpen) widget.onOpenChanged(false);
  }

  // ---------------------------------
  // ドラッグ中は指の動きにそのまま追従させる
  // ---------------------------------
  void _onDragUpdate(DragUpdateDetails details) {
    // --- 上へ動かすと開く向きなので、移動量を引く
    _openController.value -= details.primaryDelta! / _dragRange;
  }

  // ---------------------------------
  // 指を離したら開くか閉じるかへ落ち着かせる
  // ---------------------------------
  void _onDragEnd(DragEndDetails details) {
    // 位置に関わらず開閉を決めてしまう速さ（px/秒）と、開く・閉じるを分ける位置
    const flingVelocity = 400.0;
    const openThreshold = 0.5;

    // --- 離した瞬間の縦の速さ（上向きが負）
    final velocity = details.primaryVelocity ?? 0;
    // --- 勢いがあれば位置に関わらずその向きへ
    if (velocity.abs() > flingVelocity) {
      velocity < 0 ? _open() : _close();
      return;
    }
    // --- 勢いが無ければ近いほうへ寄せる
    _openController.value > openThreshold ? _open() : _close();
  }

  // ---------------------------------
  // タブの文言のスタイル（選んでいるほうを太字にする）
  // ---------------------------------
  TextStyle _tabLabelStyle({required bool isActive}) {
    return AppTextStyles.caption.copyWith(
      color: AppColors.onSurface,
      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
    );
  }

  // ---------------------------------
  // タブ（選んでいるほうは文言を線で囲み、その線が下のカード群へつながる）
  // ---------------------------------
  Widget _buildTab({
    required ListeningSheetTab tab,
    required Widget child,
    bool isFloating = false,
  }) {
    final isSelected = widget.tab == tab;

    return GestureDetector(
      onTap: () => widget.onTabSelected(tab),
      behavior: HitTestBehavior.opaque,
      child: CustomPaint(
        painter: _TabStrokePainter(
          isSelected ? _TabStroke.activeTab : _TabStroke.inactiveTab,
          isFloating: isFloating,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
          // widthFactor を 1 にして、幅の上限が渡されても中身の幅に縮ませる
          child: Align(widthFactor: 1.0, child: child),
        ),
      ),
    );
  }

  // ---------------------------------
  // タブの種類に対応する文言
  // ---------------------------------
  Widget _buildTabLabel({
    required ListeningSheetTab tab,
    required bool isBackgroundRecordingEnabled,
  }) {
    return switch (tab) {
      ListeningSheetTab.recordingOptions => _buildRecordingTabLabel(
        isBackgroundRecordingEnabled: isBackgroundRecordingEnabled,
      ),
      ListeningSheetTab.selectionActions => _buildSelectionTabLabel(),
    };
  }

  // ---------------------------------
  // 録音タブの中身: バックグラウンド録音の状態
  // ---------------------------------
  Widget _buildRecordingTabLabel({required bool isBackgroundRecordingEnabled}) {
    final labelStyle = _tabLabelStyle(
      isActive: widget.tab == ListeningSheetTab.recordingOptions,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // --- ドット（どちらの状態でも録音は続くので点滅させる）
        Dot(
          // 画面を離れても録音が続く有効側は強い注意の色、アプリ内だけの無効側は弱い注意の色にする
          color: isBackgroundRecordingEnabled
              ? AppColors.caution
              : AppColors.notice,
        ),
        const SizedBox(width: AppSpacing.s),
        // --- 文言（状態が切り替わってもタブ幅が動かないよう、長いほうの幅を確保する）
        SizedBox(
          width: _recordingStatusLabelWidth,
          child: Text(
            isBackgroundRecordingEnabled
                ? _statusLabelEnabled
                : _statusLabelDisabled,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
          ),
        ),
      ],
    );
  }

  // ---------------------------------
  // 選択操作タブの中身: 選択中のメモへの操作
  // ---------------------------------
  Widget _buildSelectionTabLabel() {
    return Text(
      '選択中の${_selectionCountFormat.format(widget.selectedCount)}件を操作',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _tabLabelStyle(
        isActive: widget.tab == ListeningSheetTab.selectionActions,
      ),
    );
  }

  // ---------------------------------
  // 帯（閉じていても見えている、シートの上端）
  // ---------------------------------
  Widget _buildBand({required bool isBackgroundRecordingEnabled}) {
    final tabOrder = ref.watch(listeningSheetTabOrderProvider);

    return SizedBox(
      height: _bandHeight,
      // --- 下線は帯の全幅に引いておき、その上へタブを重ねる
      child: CustomPaint(
        painter: const _TabStrokePainter(_TabStroke.baseline),
        // --- タブが画面幅を超えたら横へスクロールし、長押しで任意の位置へ並び替える
        child: ReorderableListView.builder(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          buildDefaultDragHandles: false,
          clipBehavior: Clip.none,
          itemCount: tabOrder.length,
          itemBuilder: (context, index) {
            final tab = tabOrder[index];
            return _TabReorderDragStartListener(
              key: ValueKey(tab.storageId),
              index: index,
              enabled: tabOrder.length > 1,
              child: _buildTab(
                tab: tab,
                child: _buildTabLabel(
                  tab: tab,
                  isBackgroundRecordingEnabled: isBackgroundRecordingEnabled,
                ),
              ),
            );
          },
          onReorderStart: (_) {
            // 長押しが成立し、タブが浮いたことを小さな振動でも伝える
            HapticFeedback.selectionClick();
          },
          onReorder: (oldIndex, newIndex) {
            ref
                .read(listeningSheetTabOrderProvider.notifier)
                .reorder(oldIndex, newIndex);
          },
          proxyDecorator: (_, index, animation) {
            final draggedTab = tabOrder[index];
            return AnimatedBuilder(
              animation: animation,
              child: _buildTab(
                tab: draggedTab,
                isFloating: true,
                child: _buildTabLabel(
                  tab: draggedTab,
                  isBackgroundRecordingEnabled: isBackgroundRecordingEnabled,
                ),
              ),
              builder: (context, floatingTab) {
                final progress = Curves.easeOut.transform(animation.value);
                final lift = _draggedTabLift * progress;
                return Transform.translate(
                  offset: Offset(0, -lift),
                  child: Transform.scale(
                    scale: 1 + (_draggedTabScale - 1) * progress,
                    child: floatingTab,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------
  // コピーした知らせ（カードの位置を動かさないよう、高さ 0 の箱から上へはみ出させる）
  // ---------------------------------
  Widget _buildCopyNotice() {
    return SizedOverflowBox(
      size: const Size(double.infinity, 0),
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Opacity(
          opacity: widget.isCopyNoticeVisible ? 1.0 : 0.0,
          // 箱はカードの幅いっぱいに広がるため、寄せは文字側で決める
          child: Text(
            _copyNoticeLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: AppTextStyles.micro.copyWith(
              fontSize: _copyNoticeFontSize,
              color: AppColors.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------
  // 選択中のメモへの操作カード（タイトルだけの小さなカード）
  // ---------------------------------
  Widget _buildSelectionActionCard({
    required String title,
    required VoidCallback onTap,
    Color titleColor = AppColors.onSurface,
    required bool isEnabled,
  }) {
    // 枠線の太さ（録音の選択肢の細いほうに揃える）
    const borderWidth = 1.5;

    return Opacity(
      opacity: isEnabled ? 1.0 : _disabledOpacity,
      child: PressableScale(
        onTap: isEnabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.l),
            border: Border.all(color: AppColors.onSurface, width: borderWidth),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              color: titleColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------
  // 録音の選択肢のドット（選んでいる選択肢だけ少し大きくする）
  // ---------------------------------
  Widget _buildOptionDot({required Color dotColor, required bool isSelected}) {
    // 大きさが変わっても下の文言がずれないよう、どちらも大きいほうの箱に入れる
    return SizedBox(
      width: _optionSelectedDotSize,
      height: _optionSelectedDotSize,
      child: Center(
        child: Dot(
          color: dotColor,
          size: isSelected ? _optionSelectedDotSize : _optionDotSize,
          isBlinking: false,
        ),
      ),
    );
  }

  // ---------------------------------
  // 録音の選択肢カード（タイトルと説明文を持つ）
  // ---------------------------------
  Widget _buildRecordingOptionCard({
    required String title,
    required String description,
    required Color dotColor,
    required VoidCallback onTap,
    required bool isSelected,
  }) {
    // 枠線の太さ（選んでいる選択肢だけ太くする）
    const normalBorderWidth = 1.5;
    const selectedBorderWidth = 3.0;
    final borderWidth = isSelected ? selectedBorderWidth : normalBorderWidth;

    // カードの内側の余白（枠線が太った分だけ削り、中身の位置を保つ）
    final contentPadding = AppSpacing.l - (borderWidth - normalBorderWidth);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(contentPadding),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.l),
          border: Border.all(color: AppColors.onSurface, width: borderWidth),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- 状態の色を示すドット（選んでいる選択肢は少し大きい）
            _buildOptionDot(dotColor: dotColor, isSelected: isSelected),
            const SizedBox(height: AppSpacing.xs),
            // --- タイトル
            Text(
              title,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              description,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------
  // 削除の確認ダイアログ
  // ---------------------------------
  Future<void> _confirmAndDeleteSelectedMemos() async {
    // 本文とボタンの文字の大きさ（caption の 12 では小さいので上げる）
    const dialogFontSize = 15.0;

    final isConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _deleteDialogTitle,
          style: AppTextStyles.button.copyWith(color: AppColors.onSurface),
        ),
        content: Text(
          _deleteDialogMessage,
          style: AppTextStyles.caption.copyWith(
            fontSize: dialogFontSize,
            color: AppColors.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              _deleteDialogCancelLabel,
              style: AppTextStyles.caption.copyWith(
                fontSize: dialogFontSize,
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              _deleteDialogConfirmLabel,
              style: AppTextStyles.caption.copyWith(
                fontSize: dialogFontSize,
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (isConfirmed != true || !mounted) return;
    await widget.onDeleteSelection();
  }

  // ---------------------------------
  // 選択をすべて解除するテキストボタン（文字が小さいので当たり判定を広く取る）
  // ---------------------------------
  Widget _buildClearButton({required bool isEnabled}) {
    // 指で押しやすい大きさ（iOS の目安に合わせる）
    const minTapSize = 44.0;

    // 文字の大きさ（caption の 12 では小さいので上げる）
    const labelFontSize = 15.0;

    return Opacity(
      opacity: isEnabled ? 1.0 : _disabledOpacity,
      child: GestureDetector(
        onTap: isEnabled ? widget.onClearSelection : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(
            minWidth: minTapSize,
            minHeight: minTapSize,
          ),
          // 文字の左へ当たり判定を広げる（右はカードの右端に揃える）
          padding: const EdgeInsets.only(left: AppSpacing.xxl),
          alignment: Alignment.centerRight,
          child: Text(
            _actionTitleClear,
            style: AppTextStyles.caption.copyWith(
              fontSize: labelFontSize,
              color: AppColors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------
  // 選択中のメモへの操作（削除・コピーのカードと、右下の解除）
  // ---------------------------------
  Widget _buildSelectionActionsSection() {
    // 1 件も選んでいなければ、どの操作も押せない
    final hasSelectedMemos = widget.selectedCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- 削除とコピーのカードは、領域の上端と解除ボタンの間の中央に置く
        Expanded(
          child: Center(
            child: Row(
              children: [
                // --- 削除（取り返しがつかないので、タイトルを危険の色にする）
                Expanded(
                  child: _buildSelectionActionCard(
                    title: _actionTitleDelete,
                    titleColor: AppColors.error,
                    onTap: _confirmAndDeleteSelectedMemos,
                    isEnabled: hasSelectedMemos,
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                // --- コピー（知らせは高さを持たせず、カードの上へはみ出させる）
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    // 子は既定では横に伸びないため、カードの幅を削除カードと揃える
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCopyNotice(),
                      _buildSelectionActionCard(
                        title: _actionTitleCopy,
                        onTap: widget.onCopySelection,
                        isEnabled: hasSelectedMemos,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // --- 解除はシートの右下に置く
        Align(
          alignment: Alignment.centerRight,
          child: _buildClearButton(isEnabled: hasSelectedMemos),
        ),
      ],
    );
  }

  // ---------------------------------
  // 選んだほうを設定として保存する（初めて有効にするときは開示ダイアログを挟む）
  // ---------------------------------
  Future<void> _selectBackgroundRecording(
    bool isEnabled, {
    required bool hasEverEnabled,
  }) async {
    // --- 初めて有効にするときは、開示ダイアログを出す
    var shouldShowDisclosureDialog = isEnabled && !hasEverEnabled;
    // --- 2回目以降の Android では
    if (isEnabled && !shouldShowDisclosureDialog && Platform.isAndroid) {
      // --- 通知の許可が無いときも出す
      shouldShowDisclosureDialog =
          !await Permission.notification.status.isGranted;
    }
    // --- マウントされていない場合は何もしない
    if (!mounted) return;
    // --- 開示ダイアログを出すなら
    if (shouldShowDisclosureDialog) {
      // --- 開示ダイアログを出して、同意されたかを受け取る
      final isConfirmed = await BackgroundRecordingDisclosureDialog.show(
        context,
      );
      // --- 同意が得られなければ何もしない
      if (!isConfirmed) return;
      // --- ダイアログを開いている間に画面が消えていたら何もしない
      if (!mounted) return;
    }
    // --- 設定を保存
    await ref.read(backgroundRecordingProvider.notifier).setEnabled(isEnabled);
  }

  // ---------------------------------
  // いつ録音するかの選択肢カード（2枚）
  // ---------------------------------
  Widget _buildRecordingOptionsSection({
    required bool isBackgroundRecordingEnabled,
    required bool hasEverEnabledBackgroundRecording,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- バックグラウンド録音の無効
        Expanded(
          child: _buildRecordingOptionCard(
            title: _optionTitleDisabled,
            description: _optionDescriptionDisabled,
            dotColor: AppColors.notice,
            isSelected: !isBackgroundRecordingEnabled,
            onTap: () => _selectBackgroundRecording(
              false,
              hasEverEnabled: hasEverEnabledBackgroundRecording,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.m),
        // --- バックグラウンド録音の有効
        Expanded(
          child: _buildRecordingOptionCard(
            title: _optionTitleEnabled,
            description: _optionDescriptionEnabled,
            dotColor: AppColors.caution,
            isSelected: isBackgroundRecordingEnabled,
            onTap: () => _selectBackgroundRecording(
              true,
              hasEverEnabled: hasEverEnabledBackgroundRecording,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------
  // 帯の下に出す、選んでいるタブのカード群
  // ---------------------------------
  Widget _buildPanel({
    required bool isBackgroundRecordingEnabled,
    required bool hasEverEnabledBackgroundRecording,
  }) {
    final Widget section;
    switch (widget.tab) {
      case ListeningSheetTab.recordingOptions:
        section = _buildRecordingOptionsSection(
          isBackgroundRecordingEnabled: isBackgroundRecordingEnabled,
          hasEverEnabledBackgroundRecording: hasEverEnabledBackgroundRecording,
        );
      case ListeningSheetTab.selectionActions:
        section = _buildSelectionActionsSection();
    }
    // どちらのタブでも同じ高さになるよう、ここで高さを決める
    return ColoredBox(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.l,
          _panelPaddingTop,
          AppSpacing.l,
          _panelPaddingBottom,
        ),
        child: SizedBox(height: _panelCardHeight, child: section),
      ),
    );
  }

  // ---------------------------------
  // 組み立て
  // ---------------------------------
  @override
  Widget build(BuildContext context) {
    // --- バックグラウンド録音の設定
    final backgroundRecording = ref.watch(backgroundRecordingProvider).value;
    final isBackgroundRecordingEnabled =
        backgroundRecording?.isEnabled ?? false;
    final hasEverEnabledBackgroundRecording =
        backgroundRecording?.hasEverEnabled ?? false;

    // --- 安全領域の下端
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    // --- 初回と画面サイズの変化に合わせて高さを伝え直す
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 破棄と同じフレームで走ると、片付いた notifier に書いてしまう
      if (!mounted) return;
      _publishHeight();
    });

    // ---------------------------------
    // 下端に貼り付いたシート本体（高さが開き具合に追従）
    // ---------------------------------
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedBuilder(
        // --- 開き具合が動くたびに作り直す ---
        animation: _openController,
        // --- 開き具合を高さに変えて、シートの背丈を決める ---
        builder: (context, content) {
          return SizedBox(
            height: _currentHeight + safeBottom,
            child: CustomPaint(
              // 帯の下から Safe Area の手前まで、左右へ太線を引く。
              // foregroundPainter にして、中の白い面より必ず手前へ描く。
              foregroundPainter: _SheetSideStrokePainter(
                progress: _openController.value,
                safeBottom: safeBottom,
              ),
              child: GestureDetector(
                // --- ドラッグ中は指に追従させる
                onVerticalDragUpdate: _onDragUpdate,
                // --- 指を離したら開くか閉じるかへ落ち着かせる
                onVerticalDragEnd: _onDragEnd,
                // 背景が透けていても、素通りして後ろの一覧に触れないよう受け止める
                behavior: HitTestBehavior.opaque,
                // --- シートの見た目（土台は塗らないので、タブの外は一覧がそのまま見える） ---
                child: Column(
                  children: [
                    // 中身は常に自然な高さで並べ、シートが低い間は下へはみ出させて隠す
                    Expanded(
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          minHeight: 0,
                          maxHeight: double.infinity,
                          child: content,
                        ),
                      ),
                    ),
                    // --- 安全領域は透けさせない
                    SizedBox(
                      width: double.infinity,
                      height: safeBottom,
                      child: const ColoredBox(color: AppColors.surface),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        // ---------------------------------
        // シートの中身
        // ---------------------------------
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- シートを閉じていても見えるエリア
            _buildBand(
              isBackgroundRecordingEnabled: isBackgroundRecordingEnabled,
            ),
            // --- シートを開いたときに見えるエリア
            _buildPanel(
              isBackgroundRecordingEnabled: isBackgroundRecordingEnabled,
              hasEverEnabledBackgroundRecording:
                  hasEverEnabledBackgroundRecording,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------
// 開いたシートの左右線
//
//   帯のベースラインから Safe Area の手前まで左右へ線を下ろす。
//   Safe Area 内には左右線・下線とも描かない。
// ---------------------------------
class _SheetSideStrokePainter extends CustomPainter {
  const _SheetSideStrokePainter({
    required this.progress,
    required this.safeBottom,
  });

  final double progress;
  final double safeBottom;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final inset = _tabStrokeWidth / 2;
    final top = _bandHeight - inset;
    final bottom = size.height - safeBottom;
    final paint = Paint()
      ..color = AppColors.onSurface
      ..strokeWidth = _tabStrokeWidth
      ..style = PaintingStyle.stroke;

    final left = inset;
    final right = size.width - inset;

    canvas.drawLine(Offset(left, top), Offset(left, bottom), paint);
    canvas.drawLine(Offset(right, top), Offset(right, bottom), paint);
  }

  @override
  bool shouldRepaint(_SheetSideStrokePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.safeBottom != safeBottom;
}

// ---------------------------------
// 標準より短い長押しでタブの並び替えを始める
// ---------------------------------
class _TabReorderDragStartListener extends ReorderableDragStartListener {
  const _TabReorderDragStartListener({
    super.key,
    required super.child,
    required super.index,
    super.enabled,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return DelayedMultiDragGestureRecognizer(
      delay: _tabReorderLongPressDuration,
      debugOwner: this,
    );
  }
}

// ---------------------------------
// タブの線の種類
// ---------------------------------
enum _TabStroke {
  // 帯の全幅に引く下線（タブはこの上に重ねる）
  baseline,
  // 文言を囲む枠（選んでいるタブ。下は開けて、下の中身につなげる）
  activeTab,
  // 文言を囲む枠（選んでいないタブ。下線をその手前に通して奥に見せる）
  inactiveTab,
}

// ---------------------------------
// 帯の線を描く
//
//   下線は帯の全幅に 1 本引き、その上にタブの枠を重ねる。選んでいるタブは
//   中を白く塗って下線を隠し、下のカード群へつながって見せる。選んでいない
//   タブは自分で下線を引き直し、線の手前に来ることで奥にあるように見せる。
// ---------------------------------
class _TabStrokePainter extends CustomPainter {
  const _TabStrokePainter(this.stroke, {this.isFloating = false});

  final _TabStroke stroke;
  final bool isFloating;

  @override
  void paint(Canvas canvas, Size size) {
    // 線は太さの半分だけ内側へ寄せて描く（そうしないと区間の外へはみ出す）
    final baselineY = size.height - _tabStrokeWidth / 2;

    // 太い線（下線と、選んでいるタブの枠）
    final strokePaint = Paint()
      ..color = AppColors.onSurface
      ..strokeWidth = _tabStrokeWidth
      ..style = PaintingStyle.stroke;

    // 細い線（選んでいないタブの枠）
    final inactiveStrokePaint = Paint()
      ..color = AppColors.onSurface
      ..strokeWidth = _inactiveTabStrokeWidth
      ..style = PaintingStyle.stroke;

    // --- 下線（帯の全幅）
    if (stroke == _TabStroke.baseline) {
      canvas.drawLine(
        Offset(0, baselineY),
        Offset(size.width, baselineY),
        strokePaint,
      );
      return;
    }

    final isActive = stroke == _TabStroke.activeTab;

    // 浮いているタブは帯のベースラインへ重ならない位置で面と側線を止める。
    // これにより、タブ自身の下辺は消しつつ、背後のベースラインは常に見える。
    final bottom = isFloating ? baselineY - _tabStrokeWidth / 2 : size.height;

    // 枠の線を内側へ寄せる量（太さが違うので、選んでいるかで変わる）
    final frameInset =
        (isActive ? _tabStrokeWidth : _inactiveTabStrokeWidth) / 2;

    // 枠の上端（選んでいないタブは、面の奥へ沈んで見えるようさらに下げる）
    final top = isActive ? frameInset : frameInset + _inactiveTabDepth;

    // --- 文言を囲む枠（左下から上がり、上の角を丸めて、右下へ下りる）
    final radius = Radius.circular(_tabCornerRadius);

    // 上の角の丸みが始まる高さ（縦の辺はここまで引く）
    final cornerY = _tabCornerRadius + top;

    final path = Path()
      ..moveTo(frameInset, bottom)
      ..lineTo(frameInset, cornerY)
      ..arcToPoint(Offset(_tabCornerRadius + frameInset, top), radius: radius)
      ..lineTo(size.width - _tabCornerRadius - frameInset, top)
      ..arcToPoint(Offset(size.width - frameInset, cornerY), radius: radius)
      ..lineTo(size.width - frameInset, bottom);

    // --- 枠の中は白で塗る（下辺で閉じた形が塗る範囲になる）
    canvas.drawPath(
      Path.from(path)..close(),
      Paint()..color = AppColors.surface,
    );

    // --- 枠の線
    canvas.drawPath(path, isActive ? strokePaint : inactiveStrokePaint);

    // --- 選んでいないタブは、下線を枠の手前に通して奥にあることを示す
    if (!isActive && !isFloating) {
      canvas.drawLine(
        Offset(0, baselineY),
        Offset(size.width, baselineY),
        strokePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_TabStrokePainter oldDelegate) =>
      oldDelegate.stroke != stroke || oldDelegate.isFloating != isFloating;
}
