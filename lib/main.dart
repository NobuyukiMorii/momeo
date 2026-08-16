import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/foundation/app_scroll_behavior.dart';
import 'package:momeo/foundation/app_theme.dart';
import 'package:momeo/pages/dev/console/console_page.dart';
import 'package:momeo/pages/dev/catalog/catalog_page.dart';
import 'package:momeo/pages/dev/recording/recording_app.dart';
import 'package:momeo/pages/dev/screenshot/screenshot_app.dart';
import 'package:momeo/pages/permissions/permission_controller.dart';
import 'package:momeo/pages/permissions/permission_flow_page.dart';
import 'package:momeo/pages/preparation_gate_page.dart';
import 'package:momeo/pages/splash_page.dart';
import 'package:momeo/pages/listening/listening_page.dart';
import 'package:momeo/providers/stt_providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------
  // 起動直後にキーボードを自動的に閉じる
  // ---------------------------------
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');

  // ---------------------------------
  // Android でもシステムバーの裏までコンテンツを描画する（エッジトゥエッジ）。
  // 安全領域の避け方は各画面が SafeArea や MediaQuery の padding で行う
  // ---------------------------------
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // ---------------------------------
  // ストア掲載用スクリーンショットの撮影モード
  // --dart-define=SCREENSHOT_SCENE=シーン名 でビルドしたときだけ有効になる
  // ---------------------------------
  const screenshotSceneName = String.fromEnvironment('SCREENSHOT_SCENE');
  if (screenshotSceneName.isNotEmpty) {
    runApp(const ScreenshotApp(sceneName: screenshotSceneName));
    return;
  }

  // ---------------------------------
  // サイト掲載用の画面収録モード
  // --dart-define=RECORDING_MODE=true でビルドしたときだけ有効になる
  // ---------------------------------
  const recordingMode = bool.fromEnvironment('RECORDING_MODE');
  if (recordingMode) {
    // 収録した映像に時計や電池を写したくないのでステータスバーを消す
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
    runApp(const RecordingApp());
    return;
  }

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
      scrollBehavior: const AppScrollBehavior(),
      home: const RootView(),
    );
  }
}

// ---------------------------------
// RootView — アプリのルート画面
// Splash → Permission → 準備ゲート → メインコンテンツ の順に遷移する
// ---------------------------------
class RootView extends ConsumerStatefulWidget {
  const RootView({super.key});

  @override
  ConsumerState<RootView> createState() => _RootViewState();
}

class _RootViewState extends ConsumerState<RootView> with WidgetsBindingObserver {
  // 権限の確認を担うコントローラー（復帰時の再チェックに使う）
  final _permissionController = PermissionController();

  bool _splashFinished = false;
  bool _permissionFinished = false;

  @override
  void initState() {
    super.initState();

    // アプリ復帰の通知イベント設定（登録）
    WidgetsBinding.instance.addObserver(this);

    // ---------------------------------
    // 起動と同時に文字化エンジンの準備（メモリ読み込み）を始める。
    // ここでは発火するだけで、完了を待たない・画面もブロックしない
    // （準備できたかの確認と足止めはリスニング直前のゲートが行う）
    // ---------------------------------
    ref.read(sttEngineProvider);
  }

  @override
  void dispose() {
    // アプリ復帰の通知イベント解除（解除）
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ---------------------------------
  // アプリ復帰時
  // ---------------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // 権限の再確認
    _recheckPermissions();
  }

  // ---------------------------------
  // 権限の再確認
  // ---------------------------------
  Future<void> _recheckPermissions() async {
    // 権限フロー表示中は、その画面が自分で再チェックするため何もしない
    if (!_permissionFinished) return;

    // 権限がすべて許可されているかを確認する
    final granted = await _permissionController.isAllGranted();

    // マウントされていないか、権限がすべて許可されていれば何もしない
    if (!mounted || granted) return;

    // 権限フロー画面を再表示する
    setState(() => _permissionFinished = false);
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
    // 準備ゲート
    // ---------------------------------
    final sttEngineState = ref.watch(sttEngineProvider);
    final isSttEngineReady =
        sttEngineState.hasValue && !sttEngineState.isLoading;
    if (!isSttEngineReady) {
      return const PreparationGatePage();
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
