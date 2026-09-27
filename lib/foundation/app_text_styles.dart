import 'package:flutter/material.dart';

// アプリ全体の書体。英数字も持つ日本語書体にして、1つの文の中で書体が混ざらないようにする
// （iOS のヒラギノ。ほかの端末では標準の書体になる）
const appFontFamily = 'Hiragino Sans';

abstract final class AppTextStyles {
  static const headline = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 40 / 32,
  );

  static const button = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 20 / 20,
  );

  static const caption = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 18 / 12,
  );

  static const micro = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 8,
    fontWeight: FontWeight.w700,
    height: 8 / 8,
  );

  static const entries = [
    ('headline', headline),
    ('button', button),
    ('caption', caption),
    ('micro', micro),
  ];
}
