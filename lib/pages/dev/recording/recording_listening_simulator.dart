import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/database/app_database.dart';
import 'package:momeo/providers/listening_providers.dart';

// ============================================================
// 画面収録用のリスニングシミュレーター
//
// 実際のマイクや音声認識は使わず、ユーザーが話して VoiceMemo が
// 生成される様子を ListeningPage 上で疑似的に再現する。
// ============================================================

// ---------------------------------
// 1回分の疑似発話
// ---------------------------------
class SimulatedSpeech {
  const SimulatedSpeech({
    required this.memo,
    required this.duration,
    required this.transcriptionDelay,
    required this.pauseAfter,
  });

  // 発話後に生成されたことにするメモ
  final VoiceMemo memo;

  // ユーザーが話している状態を続ける時間
  final Duration duration;

  // 話し終えてから文字になるまでの時間（この間も「.」は増え続ける）
  final Duration transcriptionDelay;

  // メモ確定後、次の発話まで待つ時間
  final Duration pauseAfter;
}

// ---------------------------------
// 収録用の疑似リスニング処理
// ---------------------------------
class RecordingListeningSimulator extends ListeningNotifier {
  bool _stopped = false;
  DateTime? _speakingStartedAt;
  double _speakingSeconds = 0;

  // ---------------------------------
  // 空のListeningStateからシミュレーションを始める
  // ---------------------------------
  @override
  Future<ListeningState> build() async {
    _stopped = false;
    ref.onDispose(() => _stopped = true);

    unawaited(_simulateListening());

    return const ListeningState();
  }

  // ---------------------------------
  // 疑似発話を上から順番に実行する
  // ---------------------------------
  Future<void> _simulateListening() async {
    // ListeningPageを表示してから最初の発話を始めるまで少し待つ
    await Future.delayed(const Duration(milliseconds: 500));

    for (final speech in _buildSimulatedSpeeches()) {
      if (_stopped) return;

      _startSpeaking(speech);
      await Future.delayed(speech.duration);

      if (_stopped) return;

      _stopSpeaking();
      await Future.delayed(speech.transcriptionDelay);

      if (_stopped) return;

      _deliverMemo(speech.memo);
      await Future.delayed(speech.pauseAfter);
    }
  }

  // ---------------------------------
  // ユーザーが話し始めた状態を再現する
  // ---------------------------------
  void _startSpeaking(SimulatedSpeech speech) {
    final current = state.value;
    if (current == null) return;

    _speakingStartedAt = DateTime.now();
    _speakingSeconds = speech.duration.inMicroseconds / 1000000.0;
    state = AsyncData(current.withSpeechActive(true));
  }

  // ---------------------------------
  // 話し終えて、文字になるのを待っている状態を再現する
  // ---------------------------------
  void _stopSpeaking() {
    final current = state.value;
    if (current == null) return;

    _speakingStartedAt = null;
    state = AsyncData(current.withSpeechActive(false));
  }

  // ---------------------------------
  // 文字化の結果が届き、VoiceMemo が生成された状態を再現する
  // ---------------------------------
  void _deliverMemo(VoiceMemo memo) {
    final current = state.value;
    if (current == null) return;

    // 収録の台本は1発話=1ブロックなので、確定のたびに次を新しいブロックにする
    state = AsyncData(current.withMemoAdded(memo).withCurrentBlockEnded());
  }

  // ---------------------------------
  // 発話中の音量を疑似的に生成する
  // ---------------------------------
  @override
  double get latestLevel {
    final startedAt = _speakingStartedAt;
    if (startedAt == null) return 0;

    final elapsed =
        DateTime.now().difference(startedAt).inMicroseconds / 1000000.0;

    final attack = (elapsed / 0.10).clamp(0.0, 1.0);
    final release = ((_speakingSeconds - elapsed) / 0.16).clamp(0.0, 1.0);

    final syllable =
        0.55 +
        0.30 * sin(elapsed * 2 * pi * 5.4) +
        0.15 * sin(elapsed * 2 * pi * 8.9 + 1.3);
    final phrase = 0.75 + 0.25 * sin(elapsed * 2 * pi * 1.1 + 0.7);

    final level = 0.85 * attack * release * syllable * phrase;
    return level.clamp(0.0, 1.0).toDouble();
  }
}

// ---------------------------------
// 収録中に再現する疑似発話（実行順）
//
//   夜、1日を振り返りながら、頭に浮かんだことを順に話している場面。
//   用事・家族・仕事の振り返り・思いつき・買い物・小さな悩みを混ぜ、
//   LP を眺めている間（約5分）ずっと誰かが話しかけているように見せる。
//
//   人は毎回同じリズムでは話さないので、話す長さ・文字になるまでの時間・次の発話までの間を
//   1行ごとに揺らす。揺らし方は行の番号から決めるので、何度撮っても同じ動画になる
// ---------------------------------

// 1文字あたりの話す時間と、その下限・上限
const _speakingMsPerCharacter = 28;
const _minSpeakingMs = 600;
const _maxSpeakingMs = 5500;

// 考えながら話す行の割合と、そのときに話す時間が伸びる倍率
const _thinkingWhileTalkingRate = 0.15;
const _thinkingWhileTalkingFactor = 1.5;

// 話し終えてから文字になるまでの時間（基本＋文字数に比例する分＋揺らぎ）
const _baseTranscriptionMs = 200;
const _transcriptionMsPerCharacter = 3;
const _maxTranscriptionJitterMs = 500;

// 最初のメモの時刻（夜 8 時半）
const _firstMemoHour = 20;
const _firstMemoMinute = 30;

// 台本。pauseAfter を指定した行は話題の切り替わりで、その長さを目安に考え込む間を取る
const List<(String, {int? pauseAfter})> _script = [
  (
    'Okay. Long day. Let me just get everything out of my head before I forget it.',
    pauseAfter: null,
  ),
  (
    'Call the dentist before Wednesday. I keep forgetting that one.',
    pauseAfter: null,
  ),
  (
    'And the car needs an oil change. The little light came on again this morning.',
    pauseAfter: null,
  ),
  (
    'Mom\'s birthday is on the 24th. Maybe a scarf? She said her old one is falling apart.',
    pauseAfter: null,
  ),
  (
    'Or a nice teapot. She\'s been drinking a lot of tea lately.',
    pauseAfter: null,
  ),
  (
    'Actually, I could just ask Dad. He always knows what she wants but never says it.',
    pauseAfter: 2000,
  ),
  (
    'The meeting today went better than I expected. I should stop assuming the worst before these things.',
    pauseAfter: null,
  ),
  (
    'Ken\'s idea about splitting the project into two phases was really good.',
    pauseAfter: null,
  ),
  (
    'I should tell him that tomorrow. People don\'t hear that enough.',
    pauseAfter: null,
  ),
  (
    'Reply to Sarah\'s email about the budget. It\'s been three days.',
    pauseAfter: 2000,
  ),
  (
    'Idea for the weekend: take a train somewhere I\'ve never been. No plans, just walk around.',
    pauseAfter: null,
  ),
  (
    'Maybe the coast. It\'s supposed to be sunny on Saturday.',
    pauseAfter: null,
  ),
  (
    'Eggs, milk, and those coffee beans from the place near the station.',
    pauseAfter: null,
  ),
  ('Oh, and dish soap. We\'re almost out.', pauseAfter: null),
  (
    'I think I\'m tired because I\'ve been going to bed at one every night. Lights out by midnight. Seriously.',
    pauseAfter: null,
  ),
  ('Phone stays in the kitchen tonight.', pauseAfter: 2000),
  (
    'That book Yuki recommended. What was it called? Something about the ocean.',
    pauseAfter: null,
  ),
  (
    'I\'ll text her and ask. She\'ll laugh at me for forgetting again.',
    pauseAfter: null,
  ),
  (
    'Dinner tomorrow: the pasta with lemon and garlic. Quick, and I have everything except parsley.',
    pauseAfter: null,
  ),
  (
    'Why do I always buy parsley and then throw half of it away.',
    pauseAfter: null,
  ),
  ('Maybe grow some on the balcony. How hard can it be.', pauseAfter: null),
  ('Famous last words.', pauseAfter: 2000),
  (
    'I really want to start running again. Even just twice a week.',
    pauseAfter: null,
  ),
  (
    'The trick last time was going right after work, before I sat down. Once I sit down, it\'s over.',
    pauseAfter: null,
  ),
  (
    'Running shoes. Are they still in the closet? I think they\'re behind the vacuum.',
    pauseAfter: null,
  ),
  (
    'Rent goes out on the first. Check the account on Thursday.',
    pauseAfter: null,
  ),
  (
    'And cancel that streaming thing I never watch. Eleven dollars a month for nothing.',
    pauseAfter: 2000,
  ),
  (
    'Something I noticed today: I\'m much calmer when I eat lunch away from my desk.',
    pauseAfter: null,
  ),
  ('Small thing, but I want to keep doing that.', pauseAfter: null),
  (
    'The presentation next Friday. Open with the customer story, not the numbers.',
    pauseAfter: null,
  ),
  ('Numbers second. Nobody remembers a chart.', pauseAfter: null),
  (
    'Ask Tom if he can look over the slides on Wednesday afternoon.',
    pauseAfter: 2000,
  ),
  (
    'I haven\'t called Grandma in almost a month. That\'s not okay.',
    pauseAfter: null,
  ),
  ('Sunday morning. She\'s always up early. Call her then.', pauseAfter: null),
  (
    'She\'ll ask if I\'m eating properly. I\'ll say yes. Which is half true.',
    pauseAfter: 2000,
  ),
  (
    'Random thought: what if the kitchen table went by the window instead?',
    pauseAfter: null,
  ),
  ('More light in the morning. Worth trying this weekend.', pauseAfter: null),
  (
    'Return the jacket. The receipt is in the blue folder, I\'m pretty sure.',
    pauseAfter: null,
  ),
  ('Thirty days, so by the end of next week.', pauseAfter: null),
  (
    'That podcast about sleep was interesting. No screens an hour before bed.',
    pauseAfter: null,
  ),
  ('Which, again, means phone in the kitchen.', pauseAfter: 2000),
  ('Today was good, actually. Not perfect, but good.', pauseAfter: null),
  (
    'The coffee this morning, the walk to the station. The sky was ridiculous.',
    pauseAfter: null,
  ),
  ('I want to remember days like this.', pauseAfter: 2000),
  (
    'For Mika\'s party on Saturday: wine, and the board game she liked.',
    pauseAfter: null,
  ),
  (
    'Wait, Saturday was the coast. Okay, coast on Sunday then.',
    pauseAfter: null,
  ),
  ('Or next weekend. No need to cram everything in.', pauseAfter: 2000),
  (
    'Little project: a shelf by the front door. Keys, mail, sunglasses. Stop losing my keys.',
    pauseAfter: null,
  ),
  (
    'Measure the wall first. Don\'t eyeball it like last time.',
    pauseAfter: null,
  ),
  (
    'Ask the landlord about the bathroom fan. It sounds like a helicopter.',
    pauseAfter: null,
  ),
  (
    'I keep saying I\'ll learn to cook Thai food. Start with green curry.',
    pauseAfter: null,
  ),
  (
    'There\'s that shop near the office with the curry paste in a jar. Cheating, but fine.',
    pauseAfter: 2000,
  ),
  (
    'Should I take that online course? It\'s a lot of evenings.',
    pauseAfter: null,
  ),
  ('Maybe start with one module and see how it feels.', pauseAfter: null),
  ('Don\'t decide tonight. Tired brain makes bad decisions.', pauseAfter: null),
  (
    'Tom said a new café opened next to the library. Try it this week.',
    pauseAfter: 2000,
  ),
  (
    'Write a thank-you card for the Nakamuras. They really helped with the move.',
    pauseAfter: null,
  ),
  (
    'Buy stamps. Do people still buy stamps? I do, apparently.',
    pauseAfter: null,
  ),
  (
    'I was short with Ren on the phone today. Not fair. He didn\'t do anything.',
    pauseAfter: null,
  ),
  ('Apologize tomorrow. Keep it simple.', pauseAfter: null),
  (
    'The plants need water. The big one by the window looks sad.',
    pauseAfter: null,
  ),
  ('Laundry tomorrow morning, before it gets out of hand.', pauseAfter: 2000),
  ('Okay, what am I actually worried about.', pauseAfter: null),
  (
    'The review at work, mostly. But I\'ve done the work. It\'ll be fine.',
    pauseAfter: null,
  ),
  (
    'Write down three things I did well this quarter, just to have them ready.',
    pauseAfter: null,
  ),
  ('One: shipped the onboarding update on time.', pauseAfter: null),
  ('Two: helped the new people settle in.', pauseAfter: null),
  (
    'Three: stopped saying yes to every meeting. That one counts.',
    pauseAfter: 2000,
  ),
  ('Summer trip. Mom and Dad mentioned Kyoto again.', pauseAfter: null),
  ('Look at dates in early July before it gets expensive.', pauseAfter: null),
  (
    'Back up the photos. Thousands of them, just sitting on the phone.',
    pauseAfter: null,
  ),
  ('Haircut. It\'s been, what, two months?', pauseAfter: null),
  ('Book it for Saturday morning, before Mika\'s party.', pauseAfter: 2000),
  (
    'I like this. Just saying things out loud. It\'s quieter in my head now.',
    pauseAfter: null,
  ),
  ('Water bottle on the nightstand. Alarm at seven.', pauseAfter: null),
  ('Okay. I think that\'s everything.', pauseAfter: null),
  ('Good night.', pauseAfter: 3000),
];

// ---------------------------------
// 行ごとの揺らぎ（0.0 以上 1.0 未満）
//   index は行の番号、salt は何を揺らすかの区別。同じ組み合わせなら毎回同じ値になる
// ---------------------------------
double _variation(int index, int salt) {
  return ((index + 1) * 2654435761 + salt * 40503) % 1000 / 1000;
}

// ---------------------------------
// 次の発話までの間
//   すぐ言い足す・ふつうに続ける・少し考え込む、の3通りを混ぜる。
//   話題が変わる行（scriptedPauseMs あり）は、その長さを目安に前後させる
// ---------------------------------
int _pauseAfterMs(int index, int? scriptedPauseMs) {
  final roll = _variation(index, 3);
  final spread = _variation(index, 4);

  if (scriptedPauseMs != null) {
    return (scriptedPauseMs * (0.8 + 0.6 * spread)).round();
  }
  if (roll < 0.35) {
    return (300 + 600 * spread).round(); // すぐ言い足す
  }
  if (roll < 0.8) {
    return (800 + 800 * spread).round(); // ふつうに続ける
  }
  return (2000 + 1500 * spread).round(); // 少し考え込む
}

List<SimulatedSpeech> _buildSimulatedSpeeches() {
  final today = DateTime.now();
  var memoTime = DateTime(
    today.year,
    today.month,
    today.day,
    _firstMemoHour,
    _firstMemoMinute,
  );

  final speeches = <SimulatedSpeech>[];
  for (var index = 0; index < _script.length; index++) {
    final (content, :pauseAfter) = _script[index];

    // 話す長さ：文字数に比例させ、行ごとに 0.75〜1.35 倍に揺らす。ときどき考えながらゆっくり話す
    var speakingFactor = 0.75 + 0.6 * _variation(index, 1);
    if (_variation(index, 5) < _thinkingWhileTalkingRate) {
      speakingFactor *= _thinkingWhileTalkingFactor;
    }
    final speakingMs =
        (content.length * _speakingMsPerCharacter * speakingFactor)
            .round()
            .clamp(_minSpeakingMs, _maxSpeakingMs);

    // 文字になるまでの時間：長い発話ほど少し待つ
    final transcriptionMs =
        _baseTranscriptionMs +
        content.length * _transcriptionMsPerCharacter +
        (_maxTranscriptionJitterMs * _variation(index, 2)).round();

    final pauseMs = _pauseAfterMs(index, pauseAfter);

    final id = index + 1;
    speeches.add(
      SimulatedSpeech(
        memo: VoiceMemo(
          id: id,
          content: content,
          createdAt: memoTime,
          position: id,
        ),
        duration: Duration(milliseconds: speakingMs),
        transcriptionDelay: Duration(milliseconds: transcriptionMs),
        pauseAfter: Duration(milliseconds: pauseMs),
      ),
    );

    // メモの時刻は、実際にかかった時間の分だけ進める
    memoTime = memoTime.add(
      Duration(milliseconds: speakingMs + transcriptionMs + pauseMs),
    );
  }
  return speeches;
}
