import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/foundation/app_theme.dart';
import 'package:momeo/pages/dev/screenshot/screenshot_scenes.dart';
import 'package:momeo/pages/listening/listening_page.dart';
import 'package:momeo/providers/listening_providers.dart';

// ============================================================
// ストア掲載用スクリーンショットの撮影モード
// ============================================================

class ScreenshotApp extends StatelessWidget {
  const ScreenshotApp({super.key, required this.sceneName});

  final String sceneName;

  // ---------------------------------
  // ビルド
  // ---------------------------------
  @override
  Widget build(BuildContext context) {

    // ---------------------------------
    // シーンの解決
    // ---------------------------------
    final scene = findScreenshotScene(sceneName);
    if (scene == null) {
      throw StateError('未定義のスクリーンショットシーンです: $sceneName');
    }

    // ---------------------------------
    // 画面の組み立て
    // ---------------------------------
    return ProviderScope(
      overrides: [
        // リスニング画面の状態をシーンの固定データに差し替える
        listeningProvider.overrideWith(() => _ScreenshotListeningNotifier(scene)),
      ],
      child: MaterialApp(
        title: 'momeo',
        theme: AppTheme.light(),
        debugShowCheckedModeBanner: false,
        home: const ListeningPage(),
      ),
    );
  }
}

// ---------------------------------
// 固定データ版 ListeningNotifier
// ---------------------------------
class _ScreenshotListeningNotifier extends ListeningNotifier {
  _ScreenshotListeningNotifier(this._scene);

  final ScreenshotScene _scene;

  // ---------------------------------
  // 初期状態（パイプラインは起動しない）
  // ---------------------------------
  @override
  Future<ListeningState> build() async {
    return ListeningState(
      memos: _scene.memos,
      speechActive: _scene.speechActive,
    );
  }

  // ---------------------------------
  // 擬似的な発話音量
  // ---------------------------------
  @override
  double get latestLevel {
    if (!_scene.speechActive) return 0;
    final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final wave =
        0.45 + 0.25 * sin(t * 5.1) + 0.15 * sin(t * 11.7) + 0.10 * sin(t * 2.3);
    return wave.clamp(0.05, 0.9).toDouble();
  }
}
