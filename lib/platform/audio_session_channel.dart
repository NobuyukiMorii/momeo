import 'package:flutter/services.dart';

// ============================================================
// 他のアプリの音に録音を合わせるための窓口
//
//   Swift / Kotlin 側の AudioSessionChannel と対。録音そのものは record が扱い、
//   ここでは record が持たない問い合わせ・イヤホンの手放し・機器の抜き差しの知らせを扱う。
//   Android にあるのは isOtherAudioPlaying だけで、残りは iOS のみ。
// ============================================================

class AudioSessionChannel {
  static const MethodChannel _channel = MethodChannel('jp.momeo/audio_session');
  static const EventChannel _deviceChanges =
      EventChannel('jp.momeo/audio_session/device_changes');

  // イヤホンなどの機器がつながった・外れたときに流れる（iOS のみ）
  static Stream<void> get deviceChanges =>
      _deviceChanges.receiveBroadcastStream().map((_) {});

  // 他のアプリが音を鳴らしているか
  static Future<bool> isOtherAudioPlaying() async {
    final isPlaying = await _channel.invokeMethod<bool>('isOtherAudioPlaying');
    return isPlaying ?? false;
  }

  // 今の録音が Bluetooth のマイク（通話用の HFP）を使っているか（iOS のみ）
  static Future<bool> isBluetoothMicInUse() async {
    final inUse = await _channel.invokeMethod<bool>('isBluetoothMicInUse');
    return inUse ?? false;
  }

  // 録音を止めずに Bluetooth のマイクを手放し、イヤホンを音楽用（A2DP）に戻す（iOS のみ。背面では失敗する）
  static Future<void> releaseBluetoothMic() {
    return _channel.invokeMethod<void>('releaseBluetoothMic');
  }

  // 録音を閉じたあとに、セッションごと手放す（iOS のみ。イヤホンを通話用のまま残さない）
  static Future<void> releaseAudioSession() {
    return _channel.invokeMethod<void>('releaseAudioSession');
  }
}
