import 'dart:typed_data';

import 'package:flutter/services.dart';

// ============================================================
// OS 内蔵の文字起こしの窓口
//
//   iOS は SpeechTranscriber、Android は端末内の SpeechRecognizer が、同じチャンネル名・メソッド名で応える。
//   VAD で区切った1発話ぶんの音（16kHz・Float32）を渡すと、テキストが返る。
// ============================================================

class OsTranscriberChannel {
  static const MethodChannel _channel = MethodChannel(
    'jp.momeo/os_transcriber',
  );

  // 使えるかを確かめる。言語のモデルが端末に無ければ、OS にダウンロードを頼む
  static Future<OsTranscriberStatus> prepare() async {
    final reply = await _channel.invokeMapMethod<String, Object?>('prepare');
    return OsTranscriberStatus(
      state: OsTranscriberState.fromName(reply?['state']),
      detail: '${reply?['detail'] ?? '-'}',
    );
  }

  // 1発話ぶんの音を文字化する
  static Future<String> transcribe(Float32List samples) async {
    final text = await _channel.invokeMethod<String>('transcribe', samples);
    return text ?? '';
  }
}

// prepare の返事
enum OsTranscriberState {
  ready, // すぐ使える
  downloading, // 対応している言語だが、言語のモデルのダウンロードが終わっていない
  unsupported; // 端末か言語が対応していない

  // ネイティブから届いた名前を読む。知らない名前は使えない扱いにする
  static OsTranscriberState fromName(Object? name) {
    return OsTranscriberState.values.firstWhere(
      (state) => state.name == name,
      orElse: () => OsTranscriberState.unsupported,
    );
  }
}

class OsTranscriberStatus {
  const OsTranscriberStatus({required this.state, required this.detail});

  final OsTranscriberState state;
  final String detail; // 使える言語や、使えない理由の説明
}
