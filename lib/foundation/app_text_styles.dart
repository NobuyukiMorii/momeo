import 'package:flutter/material.dart';

abstract final class AppTextStyles {
  static const headline = TextStyle(
    fontFamily: 'Inter',
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 40 / 32,
  );

  static const button = TextStyle(
    fontFamily: 'Inter',
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 20 / 20,
  );

  static const caption = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 18 / 12,
  );

  static const micro = TextStyle(
    fontFamily: 'Inter',
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
