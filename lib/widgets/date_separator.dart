import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/foundation/app_text_styles.dart';

// 日付の文字の大きさ
const _labelFontSize = 17.0;

// 日付の両側へ伸ばす線の太さ
const _lineThickness = 2.0;

// =====================================================================
// DateSeparator — ボイスカード一覧で、日付が変わる境目に挟む区切り
//
//   「──── 今日 ────」のように、日付を真ん中に置いて左右へ線を伸ばす。
//   左右が対称なので、端末の書字方向が変わっても見え方は変わらない。
// =====================================================================
class DateSeparator extends StatelessWidget {
  const DateSeparator({super.key, required this.label});

  // 区切りに出す文字（「今日」「昨日」「9月8日」など）
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: _SeparatorLine()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
          child: Text(
            label,
            style: AppTextStyles.caption.copyWith(
              fontSize: _labelFontSize,
              color: AppColors.onSurface,
            ),
          ),
        ),
        const Expanded(child: _SeparatorLine()),
      ],
    );
  }
}

// 日付の左右へ伸びる線
class _SeparatorLine extends StatelessWidget {
  const _SeparatorLine();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: _lineThickness,
      thickness: _lineThickness,
      color: AppColors.onSurface,
    );
  }
}
