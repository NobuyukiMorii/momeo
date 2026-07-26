import 'package:momeo/database/app_database.dart';

// ---------------------------------
// シーン定義
// ---------------------------------

class ScreenshotScene {
  const ScreenshotScene({
    required this.name,
    this.memos = const [],
    this.speechActive = false,
  });

  // --dart-define=SCREENSHOT_SCENE に渡す識別子
  final String name;

  // リスニング画面に表示する確定済みメモ（新しい順）
  final List<VoiceMemo> memos;

  // 発話中（アクティブカードあり）の画面にするか
  final bool speechActive;
}

// ---------------------------------
// シーンの検索
// ---------------------------------
ScreenshotScene? findScreenshotScene(String name) {
  for (final scene in buildScreenshotScenes()) {
    if (scene.name == name) return scene;
  }
  return null;
}

// ---------------------------------
// シーン一覧
// ---------------------------------
List<ScreenshotScene> buildScreenshotScenes() {
  final demoMemos = _buildDemoMemos();

  // ---------------------------------
  // デモメモの切り出し
  // ---------------------------------
  List<VoiceMemo> newestFirst(int count) =>
      demoMemos.take(count).toList().reversed.toList();

  // ---------------------------------
  // 一覧（掲載順）
  // ---------------------------------
  return [
    // ---------------------------------
    // リスニング: 波線のみ
    // ---------------------------------
    const ScreenshotScene(name: 'listening_idle'),

    // ---------------------------------
    // リスニング: 発話中＋確定1枚
    // ---------------------------------
    ScreenshotScene(
      name: 'listening_first_memo',
      memos: newestFirst(1),
      speechActive: true,
    ),

    // ---------------------------------
    // リスニング: 発話中＋確定3枚
    // ---------------------------------
    ScreenshotScene(
      name: 'listening_growing_memos',
      memos: newestFirst(3),
      speechActive: true,
    ),

    // ---------------------------------
    // リスニング: 発話中＋確定5枚
    // ---------------------------------
    ScreenshotScene(
      name: 'listening_many_memos',
      memos: newestFirst(5),
      speechActive: true,
    ),

    // ---------------------------------
    // リスニング: 確定メモの一覧9枚（発話なし）
    // ---------------------------------
    ScreenshotScene(name: 'listening_memo_list', memos: newestFirst(9)),
  ];
}

// ---------------------------------
// デモメモ（古い順）
// ---------------------------------
List<VoiceMemo> _buildDemoMemos() {
  final today = DateTime.now();

  // ---------------------------------
  // メモ1件の生成
  // ---------------------------------
  VoiceMemo memoAt(int id, int hour, int minute, String content) => VoiceMemo(
        id: id,
        content: content,
        createdAt: DateTime(today.year, today.month, today.day, hour, minute),
      );

  // ---------------------------------
  // 例文（サイトの Concept 節・画面収録の台本と同じ文言）
  // ---------------------------------
  return [
    memoAt(1, 9, 41, '流れゆく思考をそっと残すために作りました。'),
    memoAt(2, 9, 41, '今考えてること、アプリに話しかけてください。'),
    memoAt(3, 9, 42, '未来のこと。'),
    memoAt(4, 9, 42, '仕事のこと。'),
    memoAt(5, 9, 43, '人間関係のこと。'),
    memoAt(6, 9, 43, '今日の晩ごはん。'),
    memoAt(7, 9, 44, '時の流れの中で生まれ、薄れ、消えていく思考。'),
    memoAt(8, 9, 44, 'それが消えてしまう前に、そっと残しておくために。'),
    memoAt(9, 9, 44, 'momeo'),
  ];
}
