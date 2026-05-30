import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/foundation/app_text_styles.dart';

class IntroSettingLayout extends StatelessWidget {
  const IntroSettingLayout({
    super.key,
    this.step,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String? step;
  final Widget title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          children: [
            // ---------------------------------
            // ステップ表示（「1/2」など）
            // ---------------------------------
            if (step != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.l),
                child: Text(
                  step!,
                  style: AppTextStyles.headline.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ),

            const Spacer(),

            // ---------------------------------
            // 見出しエリア
            // ---------------------------------
            SizedBox(
              width: double.infinity,
              child: title,
            ),

            const SizedBox(height: AppSpacing.l),

            // ---------------------------------
            // ボタン領域（非表示でも高さを確保してタイトル位置を固定）
            // ---------------------------------
            Visibility(
              visible: actionLabel != null,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: actionLabel != null ? onAction : null,
                  child: Text(actionLabel ?? ''),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
