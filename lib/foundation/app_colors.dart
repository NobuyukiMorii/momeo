import 'package:flutter/material.dart';

abstract final class AppColors {
  static const surface = Color(0xFFFFFFFF);
  static const onSurface = Color(0xFF111827);
  static const onSurfaceVariant = Color(0xFF6B7280);
  static const outline = Color(0xFFE5E7EB);
  static const primary = Color(0xFFEF4444);
  static const onPrimary = Color(0xFFFFFFFF);
  static const error = Color(0xFFEF4444);
  static const tertiary = Color(0xFFF4C542);

  static const entries = [
    ('surface', surface),
    ('onSurface', onSurface),
    ('onSurfaceVariant', onSurfaceVariant),
    ('outline', outline),
    ('primary', primary),
    ('onPrimary', onPrimary),
    ('error', error),
    ('tertiary', tertiary),
  ];

  static const colorScheme = ColorScheme(
    brightness: Brightness.light,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    primary: primary,
    onPrimary: onPrimary,
    error: error,
    onError: onPrimary,
    tertiary: tertiary,
    secondary: primary,
    onSecondary: onPrimary,
  );
}
