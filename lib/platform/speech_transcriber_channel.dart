import 'dart:typed_data';

import 'package:flutter/services.dart';

// ============================================================
// OS 内蔵の文字起こしの窓口
//
//   iOS は SpeechTranscriber（iOS 26 以上・Swift 側の SpeechTranscriberChannel）、
//   Android は端末内の SpeechRecognizer（Android 13 以上・Kotlin 側の SpeechRecognizerChannel）。
//   どちらも同じチャンネル名・メソッド名で応える。
//   VAD で区切った1発話ぶんの音（16kHz・Float32）を渡すと、テキストが返る。
//   言語は OS の「優先する言語」のうち、対応している最初のもの。
// ============================================================

class SpeechTranscriberChannel {
  static const MethodChannel _channel = MethodChannel(
    'jp.momeo/speech_transcriber',
  );

  // 使えるかを確かめ、端末にモデルが無ければ OS にダウンロードさせる
  static Future<SpeechTranscriberStatus> prepare() async {
    final outcome = await _channel.invokeMapMethod<String, Object?>('prepare');
    return SpeechTranscriberStatus(
      available: outcome?['available'] == true,
      detail: '${outcome?['detail'] ?? '-'}',
    );
  }

  // 1発話ぶんの音を文字化する
  static Future<String> transcribe(Float32List samples) async {
    final text = await _channel.invokeMethod<String>('transcribe', samples);
    return text ?? '';
  }
}

class SpeechTranscriberStatus {
  const SpeechTranscriberStatus({
    required this.available,
    required this.detail,
  });

  final bool available;
  final String detail; // 使えるときは言語と音声形式、使えないときはその理由
}
