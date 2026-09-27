import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// アプリ全体の書体。英数字も持つ日本語書体にして、1つの文の中で書体が混ざらないようにする
// （iOS は端末のヒラギノ、Android は同梱の Noto Sans JP）
final appFontFamily = defaultTargetPlatform == TargetPlatform.iOS
    ? 'Hiragino Sans'
    : 'Noto Sans JP';

abstract final class AppTextStyles {
  static final headline = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 40 / 32,
  );

  static final button = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 20 / 20,
  );

  static final caption = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 18 / 12,
  );

  static final micro = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 8,
    fontWeight: FontWeight.w700,
    height: 8 / 8,
  );

  static final entries = [
    ('headline', headline),
    ('button', button),
    ('caption', caption),
    ('micro', micro),
  ];
}
