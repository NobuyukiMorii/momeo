import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_radius.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/foundation/app_text_styles.dart';

// ヘッダーの高さ
const listeningHeaderHeight = 56.0;

// 入力欄がヘッダーの上下に残す余白
const _fieldMargin = AppSpacing.xs;

// 入力欄の枠線の太さ
const _fieldBorderWidth = 1.5;

// 虫めがねと消すボタンの大きさ
const _iconSize = 20.0;

// 入力文字の大きさ
const _inputFontSize = 15.0;

class ListeningHeader extends StatelessWidget {
  const ListeningHeader({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onCleared,
  });

  // 入力中のキーワード
  final TextEditingController controller;

  // カーソルが当たっているか。入力欄の外を触ると画面側が外す
  final FocusNode focusNode;

  // クリアボタンを押したときの通知
  final VoidCallback onCleared;

  // ---------------------------------
  // テキストフィールド
  // ---------------------------------
  Widget _buildInput() {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      // 改行させず、確定でキーボードを閉じる
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => focusNode.unfocus(),
      cursorColor: AppColors.onSurface,
      style: AppTextStyles.caption.copyWith(
        fontSize: _inputFontSize,
        color: AppColors.onSurface,
        height: 1,
      ),
      // 枠線も余白もプレイスホルダーも持たせず、文字だけを置く
      decoration: const InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
      ),
    );
  }

  // ---------------------------------
  // 入力欄をタップしたときのイベント
  // ---------------------------------
  void _toggleInput() {
    // --- カーソルが当たっていれば
    if (focusNode.hasFocus) {
      // --- カーソルを外してキーボードを閉じる
      focusNode.unfocus();
      return;
    }
    // --- カーソルが当たっていなければ
    focusNode.requestFocus(); // カーソルを当ててキーボードを開く
  }

  // ---------------------------------
  // クリアボタンを押したときのイベント
  // ---------------------------------
  void _clearAll() {
    controller.clear();
    focusNode.unfocus();
    onCleared();
  }

  // ---------------------------------
  // クリアボタン
  // ---------------------------------
  Widget _buildClearButton() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value.text.isEmpty) return const SizedBox.shrink();
        return GestureDetector(
          onTap: _clearAll,
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.xs,
              right: AppSpacing.l,
              top: AppSpacing.m,
              bottom: AppSpacing.m,
            ),
            child: Icon(
              Icons.close,
              size: _iconSize,
              color: AppColors.onSurface,
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------
  // 組み立て
  // ---------------------------------
  @override
  Widget build(BuildContext context) {

    // 安全領域の上端
    final safeAreaTop = MediaQuery.paddingOf(context).top;

    return SizedBox(
      height: safeAreaTop + listeningHeaderHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ---------------------------------
          // 背景の上半分
          // ---------------------------------
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: safeAreaTop + listeningHeaderHeight / 2,
            child: const ColoredBox(color: AppColors.surface),
          ),
          // ---------------------------------
          // 入力欄
          // ---------------------------------
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.l,
              safeAreaTop + _fieldMargin,
              AppSpacing.l,
              _fieldMargin,
            ),
            child: GestureDetector(
              onTap: _toggleInput,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.only(left: AppSpacing.l),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: AppColors.onSurface,
                    width: _fieldBorderWidth,
                  ),
                ),
                child: Row(
                  children: [
                    // --------------------
                    // 検索アイコン
                    // --------------------
                    const Icon(
                      Icons.search,
                      size: _iconSize,
                      color: AppColors.onSurface,
                    ),
                    // --------------------
                    // テキストフィールド
                    // --------------------
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: _buildInput()),
                    // --------------------
                    // クリアボタン
                    // --------------------
                    _buildClearButton(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
