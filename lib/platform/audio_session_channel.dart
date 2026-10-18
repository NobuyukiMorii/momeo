import 'package:flutter/services.dart';

// ============================================================
// 他のアプリの音に録音を合わせるための窓口
//
//   Swift 側の AudioSessionChannel と対。録音そのものは record が扱い、
//   ここでは record が持たないセッションの手放しを扱う。今は iOS のみ。
// ============================================================

class AudioSessionChannel {
  static const MethodChannel _channel = MethodChannel('jp.momeo/audio_session');

  // 録音を閉じたあとに、セッションごと手放す（iOS のみ。イヤホンを通話用のまま残さない）
  static Future<void> releaseAudioSession() {
    return _channel.invokeMethod<void>('releaseAudioSession');
  }
}
