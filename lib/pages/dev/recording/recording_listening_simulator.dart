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
    required this.pauseAfter,
  });

  // 発話後に生成されたことにするメモ
  final VoiceMemo memo;

  // ユーザーが話している状態を続ける時間
  final Duration duration;

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

      _finishSpeaking(speech.memo);
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
  // 発話終了とVoiceMemoの生成を再現する
  // ---------------------------------
  void _finishSpeaking(VoiceMemo memo) {
    final current = state.value;
    if (current == null) return;

    _speakingStartedAt = null;
    state = AsyncData(current.withSpeechActive(false).withMemoAdded(memo));
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
// ---------------------------------
List<SimulatedSpeech> _buildSimulatedSpeeches() {
  final today = DateTime.now();

  SimulatedSpeech speech(
    int id,
    int minute,
    String content, {
    required int duration,
    required int pauseAfter,
  }) {
    return SimulatedSpeech(
      memo: VoiceMemo(
        id: id,
        content: content,
        createdAt: DateTime(today.year, today.month, today.day, 9, minute),
      ),
      duration: Duration(milliseconds: duration),
      pauseAfter: Duration(milliseconds: pauseAfter),
    );
  }

  return [
    speech(
      1,
      41,
      'ただ、話すだけのアプリです。',
      duration: 900,
      pauseAfter: 1300,
    ),
    speech(2, 41, 'ふと浮かんだアイデア。', duration: 450, pauseAfter: 650),
    speech(3, 41, '一瞬のひらめき。', duration: 480, pauseAfter: 710),
    speech(
      4,
      42,
      '流れる思考をそっと残すために作られたアプリです。',
      duration: 1200,
      pauseAfter: 2050,
    ),

    // 短い4連。話すたびにメモが増える様子を速いテンポで見せる
    speech(5, 42, '未来のこと。', duration: 380, pauseAfter: 390),
    speech(6, 42, '仕事のこと。', duration: 350, pauseAfter: 330),
    speech(7, 43, '人間関係のこと。', duration: 380, pauseAfter: 390),
    speech(8, 43, '今日の晩ごはん。', duration: 380, pauseAfter: 490),

    speech(
      9,
      44,
      '時の流れの中で生まれ、薄れ、消えていく思考。',
      duration: 980,
      pauseAfter: 1420,
    ),
    speech(
      10,
      44,
      'それが消えてしまう前に、そっと残しておくために。',
      duration: 800,
      pauseAfter: 950,
    ),
  ];
}
