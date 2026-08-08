import 'package:flutter/material.dart';

// 生の色そのもの。1つの色が複数の用途を兼ねるため、用途ごとの名前は AppColors で付ける
abstract final class AppPalette {
  static const white = Color(0xFFFFFFFF);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray500 = Color(0xFF6B7280);
  static const gray900 = Color(0xFF111827);
  static const red500 = Color(0xFFEF4444);
  static const yellow500 = Color(0xFFEAB308);
  static const green600 = Color(0xFF16A34A);
  static const blue600 = Color(0xFF2563EB);

  static const entries = [
    ('white', white),
    ('gray200', gray200),
    ('gray500', gray500),
    ('gray900', gray900),
    ('red500', red500),
    ('yellow500', yellow500),
    ('green600', green600),
    ('blue600', blue600),
  ];
}
