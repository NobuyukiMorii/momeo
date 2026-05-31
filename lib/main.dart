import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_theme.dart';
import 'package:momeo/pages/dev/console/console_page.dart';
import 'package:momeo/pages/my_home_page.dart';
import 'package:momeo/pages/dev/catalog/catalog_page.dart';
import 'package:momeo/pages/splash_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: AppTheme.light(),
      home: const RootView(),
    );
  }
}

// ---------------------------------
// RootView — アプリのルート画面
// 起動時は SplashPage を表示し、完了後にメインコンテンツへ切り替える
// ---------------------------------
class RootView extends StatefulWidget {
  const RootView({super.key});

  @override
  State<RootView> createState() => _RootViewState();
}

class _RootViewState extends State<RootView> {
  bool _splashFinished = false;

  @override
  Widget build(BuildContext context) {

    // ---------------------------------
    // スプラッシュ画面
    // ---------------------------------
    if (!_splashFinished) {
      return SplashPage(
        onFinished: () {
          setState(() {
            _splashFinished = true;
          });
        },
      );
    }

    // ---------------------------------
    // メインコンテンツ
    // kDebugMode 時は ConsolePage が index 0 に入るため、
    // initialPage で MyHomePage の位置を指定する
    // ---------------------------------
    return PageView(
      controller: PageController(initialPage: kDebugMode ? 1 : 0),
      children: [
        if (kDebugMode) const ConsolePage(),
        const MyHomePage(title: 'Flutter Demo Home Page'),
        if (kDebugMode) const CatalogPage(),
      ],
    );
  }
}
