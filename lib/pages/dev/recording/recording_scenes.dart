import 'package:momeo/database/app_database.dart';

// ============================================================
// サイト掲載用の画面収録の台本
//
//   スクリーンショットの台本（screenshot_scenes.dart）が「ある一瞬の状態」を
//   1つ持つのに対し、こちらは「状態の列と、それぞれを何秒見せるか」を持つ。
//   台本を再生するのは recording_app.dart。
// ============================================================

// ---------------------------------
// シーン定義
// ---------------------------------
class RecordingScene {
  const RecordingScene({
    required this.name,
    required this.leadIn,
    required this.steps,
    required this.tail,
  });

  // --dart-define=RECORDING_SCENE に渡す識別子
  final String name;

  // 再生を始めるまでの静かな間。アプリの起動直後のちらつきを収録から
  // 切り落とす余裕をここで作る
  final Duration leadIn;

  // 発話1回ぶんを1ステップとして、上から順に再生する
  final List<RecordingStep> steps;

  // 最後のカードを見せたまま止めておく時間
  final Duration tail;
}

// ---------------------------------
// 発話1回ぶん
// ---------------------------------
class RecordingStep {
  const RecordingStep({
    required this.memo,
    required this.speaking,
    required this.pause,
  });

  // このステップで確定するメモ
  final VoiceMemo memo;

  // アクティブカード（ドット）を出して発話中に見せる時間
  final Duration speaking;

  // メモを確定してから次の発話が始まるまでの間。
  // 確定直後にタイピング演出が走るため、その所要時間（1文字 30ms、
  // 最長 1800ms）を見込んだ長さにする
  final Duration pause;
}

// ---------------------------------
// シーンの検索
// ---------------------------------
RecordingScene? findRecordingScene(String name) {
  for (final scene in buildRecordingScenes()) {
    if (scene.name == name) return scene;
  }
  return null;
}

// ---------------------------------
// シーン一覧
// ---------------------------------
List<RecordingScene> buildRecordingScenes() {
  return [
    _buildConceptScene(),
  ];
}

// ---------------------------------
// concept — サイトの Concept の文章をそのまま話していくシーン
//
//   文言は docs/index.html の Concept 節と揃えてある。
//   1文＝1枚にしてあるのは、発話が途切れたところで1枚確定する
//   実際の区切り方に合わせるため
// ---------------------------------
RecordingScene _buildConceptScene() {
  final today = DateTime.now();

  // ---------------------------------
  // ステップ1件の生成（時間はミリ秒で書くほうが一覧として読みやすい）
  // ---------------------------------
  RecordingStep step(
    int id,
    int minute,
    String content, {
    required int speaking,
    required int pause,
  }) {
    return RecordingStep(
      memo: VoiceMemo(
        id: id,
        content: content,
        createdAt: DateTime(today.year, today.month, today.day, 9, minute),
      ),
      speaking: Duration(milliseconds: speaking),
      pause: Duration(milliseconds: pause),
    );
  }

  return RecordingScene(
    name: 'concept',
    leadIn: const Duration(milliseconds: 4000),
    tail: const Duration(milliseconds: 1800),
    steps: [
      step(1, 41, 'momeoというアプリ名は、「memo」と「moment」の組み合わせです。',
          speaking: 900, pause: 1300),
      step(2, 41, 'ふと浮かんだ考えを残す、メモ。', speaking: 450, pause: 650),
      step(3, 41, '生まれては過ぎていく、日々の一瞬。', speaking: 480, pause: 710),
      step(4, 42, 'momeo は、そんな一瞬の中に生まれる思考を、できるだけ自然に残すためにつくられた、音声ファーストのメモアプリです。',
          speaking: 1200, pause: 2050),

      // 短い4連。ここだけテンポを上げて、話すたびに増える感じを見せる
      step(5, 42, 'これからのこと。', speaking: 380, pause: 390),
      step(6, 42, '仕事のこと。', speaking: 350, pause: 330),
      step(7, 43, '人間関係のこと。', speaking: 380, pause: 390),
      step(8, 43, '何を食べようか。', speaking: 380, pause: 490),

      step(9, 44, 'ふと浮かんだ考えの多くは、たちまち思考の流れの中で薄れ、やがて消えてしまいます。',
          speaking: 980, pause: 1420),
      step(10, 44, 'momeoは、その思考が消えてしまう前に、そっと残しておきます。',
          speaking: 800, pause: 950),
    ],
  );
}
