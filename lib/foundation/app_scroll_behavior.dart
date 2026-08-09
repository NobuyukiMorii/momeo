import 'package:flutter/material.dart';

// ---------------------------------
// スクロール端の挙動を iOS に揃える
// ---------------------------------
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  // ---------------------------------
  // iOS と同じバウンス設定
  // ---------------------------------
  static const _bouncingPhysics = BouncingScrollPhysics(
    parent: RangeMaintainingScrollPhysics(),
  );

  // ---------------------------------
  // Android の引き伸ばし表現を出さない
  // ---------------------------------
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // --- 包まずに返すとインジケーターが付かない
    return child;
  }

  // ---------------------------------
  // Android もバウンスにする
  // ---------------------------------
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // --- 既定が Clamping なのは Android だけ
    if (getPlatform(context) == TargetPlatform.android) {
      // --- iOS と同じバウンス
      return _bouncingPhysics;
    }
    // --- iOS はもともとバウンスなので触らない
    return super.getScrollPhysics(context);
  }
}
