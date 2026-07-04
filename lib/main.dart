import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/foundation/app_theme.dart';
import 'package:momeo/pages/dev/console/console_page.dart';
import 'package:momeo/pages/dev/catalog/catalog_page.dart';
import 'package:momeo/pages/permissions/permission_flow_page.dart';
import 'package:momeo/pages/splash_page.dart';
import 'package:momeo/pages/listening_page.dart';
import 'package:momeo/providers/stt_providers.dart';

void main() {
  // ---------------------------------
  // ProviderScope で包むと、配下のどこからでも Provider を参照できる
  // ---------------------------------
  runApp(const ProviderScope(child: MyApp()));
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
// Splash → Permission → メインコンテンツ の順に遷移する
// ---------------------------------
class RootView extends ConsumerStatefulWidget {
  const RootView({super.key});

  @override
  ConsumerState<RootView> createState() => _RootViewState();
}

class _RootViewState extends ConsumerState<RootView> {
  bool _splashFinished = false;
  bool _permissionFinished = false;

  @override
  void initState() {
    super.initState();
    // ---------------------------------
    // 起動と同時に文字化エンジンの準備（メモリ読み込み）を始める。
    // ここでは発火するだけで、完了を待たない・画面もブロックしない
    // （準備できたかの確認と足止めはリスニング直前のゲートが行う）
    // ---------------------------------
    ref.read(sttEngineProvider);
  }

  @override
  Widget build(BuildContext context) {
    // ---------------------------------
    // スプラッシュ画面
    // ---------------------------------
    if (!_splashFinished) {
      return SplashPage(
        onFinished: () {
          setState(() => _splashFinished = true);
        },
      );
    }

    // ---------------------------------
    // 権限フロー画面
    // ---------------------------------
    if (!_permissionFinished) {
      return PermissionFlowPage(
        onFinished: () {
          setState(() => _permissionFinished = true);
        },
      );
    }

    // ---------------------------------
    // メインコンテンツ
    // kDebugMode 時は ConsolePage が index 0 に入るため、
    // initialPage で ListeningPage の位置を指定する
    // ---------------------------------
    return PageView(
      controller: PageController(initialPage: kDebugMode ? 1 : 0),
      children: [
        if (kDebugMode) const ConsolePage(),
        const ListeningPage(),
        if (kDebugMode) const CatalogPage(),
      ],
    );
  }
}
