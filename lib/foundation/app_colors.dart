import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_palette.dart';

abstract final class AppColors {

  // ---------------------------------
  // 背景と、その上に置く文字・線
  // ---------------------------------
  static const surface = AppPalette.white; // 画面やカードの背景
  static const onSurface = AppPalette.gray900; // 背景の上の文字・アイコン・輪郭線
  static const onSurfaceVariant = AppPalette.gray500; // 背景の上の、控えめな文字
  static const outline = AppPalette.gray200; // 主張させたくない区切り線

  // ---------------------------------
  // 主役のアクション
  // ---------------------------------
  static const primary = AppPalette.gray900;
  static const onPrimary = AppPalette.white;

  // ---------------------------------
  // 取り消せない操作
  // ---------------------------------
  static const error = AppPalette.red500;
  static const onError = AppPalette.white;

  // ---------------------------------
  // 状態を示す色
  // ---------------------------------
  static const caution = AppPalette.red500; // 注意を向けてほしい状態
  static const safe = AppPalette.green600; // そのままでよい状態

  // ---------------------------------
  // 文字の中の、押せる場所
  // ---------------------------------
  static const link = AppPalette.blue600;

  // ---------------------------------
  // カタログ表示用の一覧（
  // ---------------------------------
  static const entries = [
    ('surface', surface),
    ('onSurface', onSurface),
    ('onSurfaceVariant', onSurfaceVariant),
    ('outline', outline),
    ('primary', primary),
    ('onPrimary', onPrimary),
    ('error', error),
    ('onError', onError),
    ('caution', caution),
    ('safe', safe),
    ('link', link),
  ];

  // ---------------------------------
  // Material のウィジェットが既定で使う色
  // ---------------------------------
  static const colorScheme = ColorScheme(
    brightness: Brightness.light,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    outlineVariant: outline,
    surfaceContainerHighest: outline,
    primary: primary,
    onPrimary: onPrimary,
    secondary: primary,
    onSecondary: onPrimary,
    error: error,
    onError: onError,
  );
}
