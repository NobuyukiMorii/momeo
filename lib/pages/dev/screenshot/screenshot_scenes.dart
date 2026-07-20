import 'package:momeo/database/app_database.dart';

// ---------------------------------
// シーン定義
// ---------------------------------

class ScreenshotScene {
  const ScreenshotScene({
    required this.name,
    this.splashText,
    this.memos = const [],
    this.speechActive = false,
  });

  // --dart-define=SCREENSHOT_SCENE に渡す識別子
  final String name;

  // 非 null ならスプラッシュ演出の1コマを静止表示する
  final String? splashText;

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
    // スプラッシュ演出の3コマ
    const ScreenshotScene(name: 'splash_auto_start', splashText: 'Auto-start'),
    const ScreenshotScene(name: 'splash_auto_stop', splashText: 'Auto-stop'),
    const ScreenshotScene(
      name: 'splash_open_speak_saved',
      splashText: 'Open. Speak. Saved.',
    ),

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
    // リスニング: 確定メモの一覧
    // ---------------------------------
    ScreenshotScene(name: 'listening_memo_list', memos: newestFirst(5)),
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
  // 例文（差し替え可）
  // ---------------------------------
  return [
    memoAt(1, 7, 41, '今日やることを整理する まず午前中にプレゼン資料を仕上げて共有まで終わらせる'),
    memoAt(2, 7, 42, '10時の打ち合わせが終わったら駅前の郵便局に寄る'),
    memoAt(3, 7, 42, '昼は軽めに済ませて午後はレビュー対応に集中する'),
    memoAt(4, 7, 43, '帰りに牛乳と卵を買う'),
    memoAt(5, 7, 45, '夜は9時までに切り上げて明日の準備をしてから寝る'),
  ];
}
