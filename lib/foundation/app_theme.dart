import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_radius.dart';
import 'package:momeo/foundation/app_text_styles.dart';

abstract final class AppTheme {
  // 押せなくなっているボタンの、背景と文字の薄さ
  static const _disabledBackgroundOpacity = 0.08;
  static const _disabledForegroundOpacity = 0.16;

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: AppColors.colorScheme,
      scaffoldBackgroundColor: AppColors.surface,
      filledButtonTheme: FilledButtonThemeData(
        // 押せるときの色は colorScheme の primary / onPrimary から決まる
        style: FilledButton.styleFrom(
          disabledBackgroundColor: AppColors.onSurface.withValues(
            alpha: _disabledBackgroundOpacity,
          ),
          disabledForegroundColor: AppColors.onSurface.withValues(
            alpha: _disabledForegroundOpacity,
          ),
          textStyle: AppTextStyles.button,
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
      ),
    );
  }
}
