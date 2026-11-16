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

  // 発話中（「.」が出ている）の画面にするか
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
    // リスニング: 発話中＋確定1件
    // ---------------------------------
    ScreenshotScene(
      name: 'listening_first_memo',
      memos: newestFirst(1),
      speechActive: true,
    ),

    // ---------------------------------
    // リスニング: 発話中＋確定3件
    // ---------------------------------
    ScreenshotScene(
      name: 'listening_growing_memos',
      memos: newestFirst(3),
      speechActive: true,
    ),

    // ---------------------------------
    // リスニング: 発話中＋確定5件
    // ---------------------------------
    ScreenshotScene(
      name: 'listening_many_memos',
      memos: newestFirst(5),
      speechActive: true,
    ),

    // ---------------------------------
    // リスニング: 確定メモの一覧7件（発話なし）
    //   例文は 2 行の文が多いので、上端のステータスバーに重ならない 7 件までにする
    // ---------------------------------
    ScreenshotScene(name: 'listening_memo_list', memos: newestFirst(7)),
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
        position: id,
      );

  // ---------------------------------
  // 例文（夜に1日を振り返る独り言。サイトの画面の再現 docs/demo.js の台本の冒頭と同じ文言）
  // ---------------------------------
  return [
    memoAt(1, 20, 30,
        'Okay. Long day. Let me just get everything out of my head before I forget it.'),
    memoAt(2, 20, 30,
        'Call the dentist before Wednesday. I keep forgetting that one.'),
    memoAt(3, 20, 31,
        'And the car needs an oil change. The little light came on again this morning.'),
    memoAt(4, 20, 31,
        "Mom's birthday is on the 24th. Maybe a scarf? She said her old one is falling apart."),
    memoAt(5, 20, 32,
        "Or a nice teapot. She's been drinking a lot of tea lately."),
    memoAt(6, 20, 32,
        'Actually, I could just ask Dad. He always knows what she wants but never says it.'),
    memoAt(7, 20, 33,
        'The meeting today went better than I expected. I should stop assuming the worst before these things.'),
    memoAt(8, 20, 34,
        "Ken's idea about splitting the project into two phases was really good."),
    memoAt(9, 20, 34,
        "I should tell him that tomorrow. People don't hear that enough."),
  ];
}
