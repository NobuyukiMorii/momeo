import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_radius.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/foundation/app_text_styles.dart';

// ============================================================
// キーワードの検索フィールド
// ============================================================

// ---------------------------------
// 定数: 高さ
// ---------------------------------

// 検索フィールドの高さ（枠の線を含む）
const listeningSearchFieldHeight = 56.0;

// ---------------------------------
// 定数: 見た目
// ---------------------------------

// 検索フィールドを囲む線の太さ
const _borderWidth = 3.0;

// 検索フィールドの角の丸み
const _cornerRadius = AppRadius.l;

// 検索フィールドを囲む枠（白地を線で囲み、四隅を丸める）
const _boxDecoration = BoxDecoration(
  color: AppColors.surface,
  borderRadius: BorderRadius.all(Radius.circular(_cornerRadius)),
  border: Border.fromBorderSide(
    BorderSide(color: AppColors.onSurface, width: _borderWidth),
  ),
);

// 入力文字の大きさ
const _inputFontSize = 17.0;

// カーソルの太さ
const _cursorWidth = 1.0;

// カーソルの高さ
const _cursorHeight = 26.0;

// 虫めがねと消すボタンの大きさ。カーソルの高さに合わせる
const _iconSize = _cursorHeight;

// ---------------------------------
// クラス本体
// ---------------------------------
class ListeningSearchField extends StatelessWidget {
  const ListeningSearchField({
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
  // 枠とその中身
  // ---------------------------------
  Widget _buildBox() {
    return Container(
      height: listeningSearchFieldHeight,
      decoration: _boxDecoration,
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
    // 角の丸みの外側から一覧が透けないよう、背景を敷いてから枠を置く
    return ColoredBox(
      color: AppColors.surface,
      child: GestureDetector(
        // 検索フィールドのどこを触ってもカーソルを当てる
        onTap: focusNode.requestFocus,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            _buildBox(),
            // --- 上の角だけ、画面の端にも線を引く（録音設定パネルの左右の線とつながる）
            const Positioned(
              left: 0,
              top: 0,
              width: _borderWidth,
              height: _cornerRadius,
              child: ColoredBox(color: AppColors.onSurface),
            ),
            const Positioned(
              right: 0,
              top: 0,
              width: _borderWidth,
              height: _cornerRadius,
              child: ColoredBox(color: AppColors.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
