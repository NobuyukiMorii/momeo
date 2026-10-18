import AVFoundation
import Flutter

// 他のアプリの音に録音を合わせるための、AVAudioSession のネイティブブリッジ。
//   録音そのものは record プラグインが扱う。ここでは record が持たない
//   「他のアプリが鳴っているか」の問い合わせと、録音を閉じたあとのセッションの手放しを受け持つ。
enum AudioSessionChannel {
  // Dart 側と一致させるチャンネル名・メソッド名
  static let channelName = "jp.momeo/audio_session"
  static let isOtherAudioPlayingMethod = "isOtherAudioPlaying"
  static let releaseAudioSessionMethod = "releaseAudioSession"

  // 通話線（MethodChannel）を1本立て、問い合わせに応える
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case isOtherAudioPlayingMethod:
        result(AVAudioSession.sharedInstance().isOtherAudioPlaying)
      case releaseAudioSessionMethod:
        handleReleaseAudioSession(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // 録音を閉じたあとに、セッションごと手放す。
  // record は録音を閉じてもセッションを有効なままにするため、手放さないとイヤホンが通話用のまま残る
  private static func handleReleaseAudioSession(result: FlutterResult) {
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      result(nil)
    } catch {
      result(FlutterError(code: "release_audio_session_failed", message: "\(error)", details: nil))
    }
  }
}
