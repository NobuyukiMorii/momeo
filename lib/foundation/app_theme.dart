import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_radius.dart';
import 'package:momeo/foundation/app_text_styles.dart';

abstract final class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: AppColors.colorScheme,
      scaffoldBackgroundColor: AppColors.surface,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.onSurface,
          foregroundColor: AppColors.surface,
          disabledBackgroundColor: AppColors.onSurface.withValues(alpha: 0.08),
          disabledForegroundColor: AppColors.onSurface.withValues(alpha: 0.16),
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
