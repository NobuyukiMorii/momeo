import 'package:flutter/services.dart';

// ============================================================
// 他のアプリの音に録音を合わせるための窓口
//
//   Swift / Kotlin 側の AudioSessionChannel と対。録音そのものは record が扱い、
//   ここでは record が持たない問い合わせ・セッションの手放しを扱う。
//   Android にあるのは isOtherAudioPlaying だけで、残りは iOS のみ。
// ============================================================

class AudioSessionChannel {
  static const MethodChannel _channel = MethodChannel('jp.momeo/audio_session');

  // 他のアプリが音を鳴らしているか
  static Future<bool> isOtherAudioPlaying() async {
    final isPlaying = await _channel.invokeMethod<bool>('isOtherAudioPlaying');
    return isPlaying ?? false;
  }

  // 録音を閉じたあとに、セッションごと手放す（iOS のみ。イヤホンを通話用のまま残さない）
  static Future<void> releaseAudioSession() {
    return _channel.invokeMethod<void>('releaseAudioSession');
  }
}
