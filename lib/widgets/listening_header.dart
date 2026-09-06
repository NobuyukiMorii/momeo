import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_radius.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/foundation/app_text_styles.dart';

// ヘッダーの高さ
const listeningHeaderHeight = 56.0;

// ヘッダーを囲む線の太さ
const _borderWidth = 3.0;

// ヘッダーの角の丸み
const _cornerRadius = AppRadius.l;

// 線の内側にできる角の丸み
const _innerCornerRadius = _cornerRadius - _borderWidth;

// 入力文字の大きさ
const _inputFontSize = 17.0;

// カーソルの太さ
const _cursorWidth = 1.0;

// カーソルの高さ
const _cursorHeight = 26.0;

// 虫めがねと消すボタンの大きさ。カーソルの高さに合わせる
const _iconSize = _cursorHeight;

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
      cursorWidth: _cursorWidth,
      cursorHeight: _cursorHeight,
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
  // 入力欄（虫めがね・テキストフィールド・クリアボタン）
  // ---------------------------------
  Widget _buildField() {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.l),
      child: Row(
        children: [
          // --------------------
          // 検索アイコン
          // --------------------
          const Icon(Icons.search, size: _iconSize, color: AppColors.onSurface),
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
    );
  }

  // ---------------------------------
  // 組み立て
  // ---------------------------------
  @override
  Widget build(BuildContext context) {
    // 安全領域の上端
    final safeAreaTop = MediaQuery.paddingOf(context).top;

    return GestureDetector(
      // ヘッダーのどこを触っても入力欄を開閉できるようにする
      onTap: _toggleInput,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: safeAreaTop + listeningHeaderHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ---------------------------------
            // 背景と、ヘッダーを囲む線
            // ---------------------------------
            Column(
              // 子は既定では横に伸びないため、明示して画面幅いっぱいに広げる
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 安全領域は線を引かず、背景だけを敷く
                SizedBox(
                  height: safeAreaTop,
                  child: const ColoredBox(color: AppColors.surface),
                ),
                // ヘッダー本体は四辺を線で囲み、四隅を丸める。
                // 線の色で塗った土台の内側に、本体をひと回り小さく重ねる
                const Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.onSurface,
                      borderRadius: BorderRadius.all(
                        Radius.circular(_cornerRadius),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(_borderWidth),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.all(
                            Radius.circular(_innerCornerRadius),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // ---------------------------------
            // 入力欄、または入力欄の代わりの文言
            // ---------------------------------
            Padding(
              padding: EdgeInsets.only(
                left: _borderWidth,
                top: safeAreaTop + _borderWidth,
                right: _borderWidth,
                bottom: _borderWidth,
              ),
              child: _buildField(),
            ),
          ],
        ),
      ),
    );
  }
}
