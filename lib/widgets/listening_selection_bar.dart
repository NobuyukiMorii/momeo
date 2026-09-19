import 'dart:math' show max, pow;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_radius.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/widgets/pressable_scale.dart';

// ============================================================
// ListeningSelectionBar
// ============================================================

// ---------------------------------
// 定数: 線の太さ
// ---------------------------------

// 上の線
const _topBorderWidth = 1.5;

// 削除・コピーのボタンの枠線
const _buttonBorderWidth = 1.0;

// ---------------------------------
// 定数: 文字
// ---------------------------------

// メッセージの文字の大きさ
const _noticeFontSize = 12.0;

// メインコンテンツが占めるエリアの高さ
const _labelLineHeight = 18.0;

// ---------------------------------
// 定数: 高さ
// ---------------------------------

// メッセージの上下に空ける間隔
const _noticeGap = 4.0;

// 削除・コピーのボタンの、文字の上下に取る余白
const _buttonPaddingVertical = 10.0;

// 削除・コピーのボタンの高さ
const _buttonHeight =
    _labelLineHeight + _buttonPaddingVertical * 2 + _buttonBorderWidth * 2;

// メインコンテンツの下に取る余白
const _contentBottomGap = 0.0;

// 全体の高さ
const _barHeight =
    _topBorderWidth +
    _noticeGap +
    _noticeFontSize +
    _noticeGap +
    _buttonHeight +
    _contentBottomGap;

// 削除・コピーのボタンの最小の幅
const _outlinedButtonMinWidth = 72.0;

// タップの幅
const _minTapWidth = 44.0;

// 件数の欄に幅を確保しておく桁数
const _countLabelReservedDigits = 2;

// ---------------------------------
// 定数: 見た目
// ---------------------------------

// 削除・コピーのボタンを押している間の縮み具合（小さいので、カードより大きく縮める）
const _buttonPressedScale = 0.9;

// ---------------------------------
// 定数: 画面に出る文言
// ---------------------------------

const _deleteLabel = '削除';
const _copyLabel = 'コピー';
const _clearLabel = '解除';

// 削除ボタンを押したときに出す確認ダイアログの文言
const _deleteDialogTitle = '選択中のメモを削除しますか？';
const _deleteDialogMessage = '一度削除すると復元できません。';
const _deleteDialogCancelLabel = 'キャンセル';
const _deleteDialogConfirmLabel = '削除する';

// 選択件数の3桁区切り（1000 件を超えることはまず無いが、桁が読める形にしておく）
final _selectionCountFormat = NumberFormat('#,###');

// ---------------------------------
// 一覧を押し上げる高さ（バーのうち、安全領域より上に出ているぶん）
//   一覧は安全領域のぶんを自分で空けているので、それより上に出た高さだけを返す
// ---------------------------------
double listeningSelectionBarPushUpHeight({
  required double slideProgress,
  required double safeAreaBottom,
}) {
  final visibleHeight = (_barHeight + safeAreaBottom) * slideProgress;
  return max(0.0, visibleHeight - safeAreaBottom);
}

// ---------------------------------
// クラス本体
// ---------------------------------
class ListeningSelectionBar extends StatefulWidget {
  const ListeningSelectionBar({
    super.key,
    required this.slideAnimation,
    required this.selectedCount,
    required this.onDeleteSelection,
    required this.onCopySelection,
    required this.onClearSelection,
    this.notice,
  });

  // 出具合（0 = 画面の下へ隠れきり、1 = 出きり）。一覧の押し上げと同じものを受け取る
  final Animation<double> slideAnimation;

  // 選択中のメモの件数
  final int selectedCount;

  // 削除を確認したときに、選択中のメモを DB ごと消す
  final Future<void> Function() onDeleteSelection;

  // コピーボタンを押したときに、選択中のメモをクリップボードに入れる
  final VoidCallback onCopySelection;

  // 解除ボタンを押したときに、選択をすべて外す
  final VoidCallback onClearSelection;

  // 件数と操作の上に出す一言（null なら何も出さない）
  final String? notice;

  @override
  State<ListeningSelectionBar> createState() => _ListeningSelectionBarState();
}

// ---------------------------------
// 状態
// ---------------------------------
class _ListeningSelectionBarState extends State<ListeningSelectionBar> {
  // バーに出す件数（引っ込む途中で「0件」と出さないよう、最後の 1 件以上を保つ）
  int _displayedCount = 0;

  @override
  void initState() {
    super.initState();
    _displayedCount = widget.selectedCount;
  }

  // ---------------------------------
  // 1 件以上のあいだだけ、件数を追いかける
  // ---------------------------------
  @override
  void didUpdateWidget(ListeningSelectionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedCount > 0) _displayedCount = widget.selectedCount;
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
  // ボタンと件数の文言のスタイル
  // ---------------------------------
  TextStyle _buttonLabelStyle({Color color = AppColors.onSurface}) {
    return AppTextStyles.caption.copyWith(
      color: color,
      fontWeight: FontWeight.w700,
    );
  }

  // ---------------------------------
  // 件数の文言と、そのスタイル（数字は等幅にして、桁数が同じなら幅も同じにする）
  // ---------------------------------
  String _countLabel(int count) => '${_selectionCountFormat.format(count)}件選択中';

  TextStyle get _countLabelStyle => _buttonLabelStyle().copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  // ---------------------------------
  // 件数の欄の幅（確保する桁数ぶんの「9」で測り、件数が変わってもボタンをずらさない）
  // ---------------------------------
  double _countLabelWidth() {
    final digits = max(_countLabelReservedDigits, '$_displayedCount'.length);
    final widestCount = pow(10, digits).toInt() - 1;
    final painter = TextPainter(
      text: TextSpan(text: _countLabel(widestCount), style: _countLabelStyle),
      // intl にも TextDirection があり名前がぶつかるので、画面の向きをそのまま使う
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  // ---------------------------------
  // 枠で囲んだ四角いボタン（削除・コピー）
  // ---------------------------------
  Widget _buildOutlinedButton({
    required String label,
    required VoidCallback onTap,
    Color labelColor = AppColors.onSurface,
  }) {
    return PressableScale(
      onTap: onTap,
      pressedScale: _buttonPressedScale,
      child: Container(
        constraints: const BoxConstraints(minWidth: _outlinedButtonMinWidth),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: _buttonPaddingVertical,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.m),
          border: Border.all(
            color: AppColors.onSurface,
            width: _buttonBorderWidth,
          ),
        ),
        // 最小の幅まで広がった箱の中で、文字を中央に置く
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: _buttonLabelStyle(color: labelColor),
        ),
      ),
    );
  }

  // ---------------------------------
  // 解除ボタン
  // ---------------------------------
  Widget _buildClearButton() {
    return GestureDetector(
      onTap: widget.onClearSelection,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(
          minWidth: _minTapWidth,
          minHeight: _buttonHeight,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
        alignment: Alignment.center,
        child: Text(_clearLabel, style: _buttonLabelStyle()),
      ),
    );
  }

  // ---------------------------------
  // メッセージ
  // ---------------------------------
  Widget _buildNotice() {
    final notice = widget.notice;

    return SizedBox(
      height: _noticeFontSize,
      child: notice == null
          ? null
          : Align(
              alignment: Alignment.centerLeft,
              child: Text(
                notice,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // 決めた高さに収めるため、行の高さを文字の大きさに合わせる
                style: _buttonLabelStyle().copyWith(
                  fontSize: _noticeFontSize,
                  height: 1.0,
                ),
              ),
            ),
    );
  }

  // ---------------------------------
  // メインコンテンツ
  // ---------------------------------
  Widget _buildActionsRow() {
    return SizedBox(
      height: _buttonHeight,
      child: Row(
        children: [
          // --- 選択件数（欄の幅を固定し、件数が変わってもボタンの位置を保つ）
          SizedBox(
            width: _countLabelWidth(),
            child: Text(
              _countLabel(_displayedCount),
              maxLines: 1,
              style: _countLabelStyle,
            ),
          ),
          const SizedBox(width: AppSpacing.l),
          // --- 削除（取り返しがつかないので、文言を危険の色にする）
          _buildOutlinedButton(
            label: _deleteLabel,
            labelColor: AppColors.error,
            onTap: _confirmAndDeleteSelectedMemos,
          ),
          const SizedBox(width: AppSpacing.s),
          // --- コピー
          _buildOutlinedButton(
            label: _copyLabel,
            onTap: widget.onCopySelection,
          ),
          // --- 解除だけを一番右へ離す
          const Spacer(),
          _buildClearButton(),
        ],
      ),
    );
  }

  // ---------------------------------
  // 本体
  // ---------------------------------
  Widget _buildBar({required double safeAreaBottom}) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.onSurface, width: _topBorderWidth),
        ),
      ),
      // 線のぶんは Container が自分で空けるので、ここでは数えない
      padding: EdgeInsets.only(
        // 右は解除ボタンの内側の余白ぶん詰め、文字の右端を左の余白と揃える
        left: AppSpacing.l,
        right: AppSpacing.l - AppSpacing.s,
        bottom: safeAreaBottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: _noticeGap),
          _buildNotice(),
          const SizedBox(height: _noticeGap),
          _buildActionsRow(),
          const SizedBox(height: _contentBottomGap),
        ],
      ),
    );
  }

  // ---------------------------------
  // 組み立て
  // ---------------------------------
  @override
  Widget build(BuildContext context) {
    // --- キーボードが出ても変わらない値を使い、入力中も一覧を動かさない
    final safeAreaBottom = MediaQuery.viewPaddingOf(context).bottom;

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedBuilder(
        animation: widget.slideAnimation,
        child: _buildBar(safeAreaBottom: safeAreaBottom),
        builder: (context, bar) {
          // --- 隠れきっている間は何も置かない
          if (widget.slideAnimation.isDismissed) return const SizedBox.shrink();
          // --- 出具合に合わせて、下からせり上げる
          return FractionalTranslation(
            translation: Offset(0, 1 - widget.slideAnimation.value),
            child: bar,
          );
        },
      ),
    );
  }
}
