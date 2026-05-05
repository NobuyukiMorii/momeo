import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';

abstract final class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: AppColors.colorScheme,
    );
  }
}
