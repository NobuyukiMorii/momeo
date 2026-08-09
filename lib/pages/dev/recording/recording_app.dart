import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/foundation/app_scroll_behavior.dart';
import 'package:momeo/foundation/app_theme.dart';
import 'package:momeo/pages/dev/recording/recording_listening_simulator.dart';
import 'package:momeo/pages/listening/listening_page.dart';
import 'package:momeo/pages/splash_page.dart';
import 'package:momeo/providers/listening_providers.dart';

// ============================================================
// LP掲載用の画面収録モード
// ============================================================

class RecordingApp extends StatelessWidget {
  const RecordingApp({super.key});

  // ---------------------------------
  // ビルド
  // ---------------------------------
  @override
  Widget build(BuildContext context) {
    // ---------------------------------
    // 収録専用のアプリを組み立てる
    // ---------------------------------
    return ProviderScope(
      overrides: [
        // 実際のマイク入力を、収録用の疑似リスニング処理に差し替える
        listeningProvider.overrideWith(RecordingListeningSimulator.new),
      ],
      child: MaterialApp(
        title: 'momeo',
        theme: AppTheme.light(),
        scrollBehavior: const AppScrollBehavior(),
        debugShowCheckedModeBanner: false,
        home: const _RecordingFlow(),
      ),
    );
  }
}

// ---------------------------------
// 画面遷移
// ---------------------------------
class _RecordingFlow extends StatefulWidget {
  const _RecordingFlow();

  @override
  State<_RecordingFlow> createState() => _RecordingFlowState();
}

// ---------------------------------
// 遷移状態
// ---------------------------------
class _RecordingFlowState extends State<_RecordingFlow> {
  // --- 開始準備
  bool _ready = false;

  // --- 表示画面
  bool _splashFinished = false;

  // ---------------------------------
  // 初期化
  // ---------------------------------
  @override
  void initState() {
    super.initState();

    // --- 収録待ち
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _ready = true);
    });
  }

  // ---------------------------------
  // ビルド
  // ---------------------------------
  @override
  Widget build(BuildContext context) {
    // --- 待機画面
    if (!_ready) {
      return const Scaffold();
    }

    // --- スプラッシュ
    if (!_splashFinished) {
      return SplashPage(
        overrideTexts: const ['momeo'],
        onFinished: () {
          setState(() => _splashFinished = true);
        },
      );
    }

    // --- リスニング（収録用のリスニング処理）
    return const ListeningPage();
  }
}
