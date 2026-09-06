import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_radius.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/providers/settings_providers.dart';
import 'package:momeo/widgets/background_recording_disclosure_dialog.dart';
import 'package:momeo/widgets/dot.dart';
import 'package:permission_handler/permission_handler.dart';

// ============================================================
// 画面下端の領域を上下のスワイプで広げ縮めするシート
//
//   帯の左右にタブが1つずつあり、常にどちらかを選んでいる。
//   「どのタブを選んでいるか」と「シートを開いているか」は別の状態で、
//   どちらも画面側（ListeningPage）が持つ。このシートは受け取った状態を
//   高さに翻訳して描く。閉じても選んでいたタブはそのまま残る。
// ============================================================

// ---------------------------------
// シートのタブ
// ---------------------------------
enum ListeningSheetTab {
  // 帯の左: いつ録音するかの選択肢
  recordingOptions,
  // 帯の右: 選択中のメモへの操作
  selectionActions,
}

// ---------------------------------
// 定数: 高さ
// ---------------------------------

// タブの帯の高さ（閉じているときはこの帯だけが見えている）
const _bandHeight = 36.0;

// 帯の下に出すカード群の高さ（背の高い録音の選択肢に合わせた固定値）
const _panelCardHeight = 168.0;

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

// シートの土台の不透明度（タブの中・カード群・安全領域は白で塗るので透けない）
const _sheetBackgroundOpacity = 0.92;

// タブの枠線と下線の太さ（ヘッダーの入力欄の枠線に揃える）
const _tabStrokeWidth = 1.5;

// 選んでいるタブの上の角の丸み
const _tabCornerRadius = AppRadius.l;

// ---------------------------------
// 定数: 画面に出る文言
// ---------------------------------

// バックグラウンド録音の状態を伝える、帯の文言
const _statusLabelEnabled = 'ほかのアプリを使っていても録音';
const _statusLabelDisabled = 'このアプリを使っている時だけ録音';

// バックグラウンド録音の選択肢（無効側・有効側）
const _optionTitleDisabled = 'このアプリを使っている時だけ録音';
const _optionDescriptionDisabled = 'アプリがバックグラウンドに移ると録音を止め、フォアグラウンドに戻ると再開します。';
const _optionTitleEnabled = 'ほかのアプリを使っていても録音';
const _optionDescriptionEnabled =
    'ほかのアプリを使っている間や画面を消している間も、マイクで音声を録り続けます。アプリを終了すると止まります。';

// 選択中のメモへの操作（カードは削除・コピーの2枚、解除は右下のテキスト）
const _actionTitleDelete = '削除';
const _actionTitleCopy = 'コピー';
const _actionTitleClear = '解除';

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
  Widget _buildTab({required ListeningSheetTab tab, required Widget child}) {
    final isSelected = widget.tab == tab;

    return GestureDetector(
      onTap: () => widget.onTabSelected(tab),
      behavior: HitTestBehavior.opaque,
      child: CustomPaint(
        painter: _TabStrokePainter(
          isSelected ? _TabStroke.tab : _TabStroke.baseline,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
          child: Center(child: child),
        ),
      ),
    );
  }

  // ---------------------------------
  // タブが無い区間（下線だけを引く）
  // ---------------------------------
  Widget _buildTabBaseline({double? width}) {
    return SizedBox(
      width: width,
      child: const CustomPaint(painter: _TabStrokePainter(_TabStroke.baseline)),
    );
  }

  // ---------------------------------
  // 左のタブの中身: バックグラウンド録音の状態
  // ---------------------------------
  Widget _buildRecordingTabLabel({required bool isBackgroundRecordingEnabled}) {
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
        // --- 文言
        Text(
          isBackgroundRecordingEnabled
              ? _statusLabelEnabled
              : _statusLabelDisabled,
          style: _tabLabelStyle(
            isActive: widget.tab == ListeningSheetTab.recordingOptions,
          ),
        ),
      ],
    );
  }

  // ---------------------------------
  // 右のタブの中身: 選択中のメモへの操作
  // ---------------------------------
  Widget _buildSelectionTabLabel() {
    return Text(
      '選択中の${_selectionCountFormat.format(widget.selectedCount)}件を操作',
      style: _tabLabelStyle(
        isActive: widget.tab == ListeningSheetTab.selectionActions,
      ),
    );
  }

  // ---------------------------------
  // 帯（閉じていても見えている、シートの上端）
  // ---------------------------------
  Widget _buildBand({required bool isBackgroundRecordingEnabled}) {
    return SizedBox(
      height: _bandHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTabBaseline(width: AppSpacing.l),
          _buildTab(
            tab: ListeningSheetTab.recordingOptions,
            child: _buildRecordingTabLabel(
              isBackgroundRecordingEnabled: isBackgroundRecordingEnabled,
            ),
          ),
          Expanded(child: _buildTabBaseline()),
          // --- 右のタブは 1 件以上選んでいるときだけ
          if (widget.selectedCount > 0)
            _buildTab(
              tab: ListeningSheetTab.selectionActions,
              child: _buildSelectionTabLabel(),
            ),
          _buildTabBaseline(width: AppSpacing.l),
        ],
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
  }) {
    // 枠線の太さ（録音の選択肢の細いほうに揃える）
    const borderWidth = 1.5;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.l),
          border: Border.all(color: AppColors.outline, width: borderWidth),
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
    );
  }

  // ---------------------------------
  // 録音の選択肢カード（タイトルと説明文を持つ）
  // ---------------------------------
  Widget _buildRecordingOptionCard({
    required String title,
    required String description,
    required VoidCallback onTap,
    bool isSelected = false,
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
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.outline,
            width: borderWidth,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
  Widget _buildClearButton() {
    // 指で押しやすい大きさ（iOS の目安に合わせる）
    const minTapSize = 44.0;

    // 文字の大きさ（caption の 12 では小さいので上げる）
    const labelFontSize = 15.0;

    return GestureDetector(
      onTap: widget.onClearSelection,
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
    );
  }

  // ---------------------------------
  // 選択中のメモへの操作（削除・コピーのカードと、右下の解除）
  // ---------------------------------
  Widget _buildSelectionActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- 削除とコピーのカードは領域の上端に寄せる
        Row(
          children: [
            // --- 削除（取り返しがつかないので、タイトルを危険の色にする）
            Expanded(
              child: _buildSelectionActionCard(
                title: _actionTitleDelete,
                titleColor: AppColors.error,
                onTap: _confirmAndDeleteSelectedMemos,
              ),
            ),
            const SizedBox(width: AppSpacing.m),
            // --- コピー
            Expanded(
              child: _buildSelectionActionCard(
                title: _actionTitleCopy,
                onTap: widget.onCopySelection,
              ),
            ),
          ],
        ),
        // --- 解除はシートの右下に置く
        const Spacer(),
        Align(alignment: Alignment.centerRight, child: _buildClearButton()),
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _publishHeight());

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
            child: GestureDetector(
              // --- ドラッグ中は指に追従させる
              onVerticalDragUpdate: _onDragUpdate,
              // --- 指を離したら開くか閉じるかへ落ち着かせる
              onVerticalDragEnd: _onDragEnd,
              // 背景が透けていても、素通りして後ろの一覧に触れないよう受け止める
              behavior: HitTestBehavior.opaque,
              // --- シートの見た目 ---
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(
                    alpha: _sheetBackgroundOpacity,
                  ),
                ),
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
// タブの線の種類
// ---------------------------------
enum _TabStroke {
  // 下辺だけの線（選んでいないタブと、タブの間）
  baseline,
  // 文言を囲む枠（選んでいるタブ。下は開けて、下の中身につなげる）
  tab,
}

// ---------------------------------
// タブの線を描く（下線と枠がひと続きに見えるよう、同じ太さ・色で区間ごとに描く）
// ---------------------------------
class _TabStrokePainter extends CustomPainter {
  const _TabStrokePainter(this.stroke);

  final _TabStroke stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.onSurface
      ..strokeWidth = _tabStrokeWidth
      ..style = PaintingStyle.stroke;

    // 線の太さの半分（線が区間の外へはみ出さないよう、中心をこのぶん内側に寄せる）
    final inset = _tabStrokeWidth / 2;

    // --- 下辺だけの線
    if (stroke == _TabStroke.baseline) {
      final y = size.height - inset;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }

    // --- 文言を囲む枠（左下から上がり、上の角を丸めて、右下へ下りる）
    final radius = Radius.circular(_tabCornerRadius);
    final path = Path()
      ..moveTo(inset, size.height)
      ..lineTo(inset, _tabCornerRadius + inset)
      ..arcToPoint(Offset(_tabCornerRadius + inset, inset), radius: radius)
      ..lineTo(size.width - _tabCornerRadius - inset, inset)
      ..arcToPoint(
        Offset(size.width - inset, _tabCornerRadius + inset),
        radius: radius,
      )
      ..lineTo(size.width - inset, size.height);

    // --- 枠の中は白で塗る（下辺で閉じた形が塗る範囲になる）
    canvas.drawPath(
      Path.from(path)..close(),
      Paint()..color = AppColors.surface,
    );

    // --- 枠の線
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TabStrokePainter oldDelegate) =>
      oldDelegate.stroke != stroke;
}
