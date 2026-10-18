import AVFoundation
import Flutter

// 他のアプリの音に録音を合わせるための、AVAudioSession のネイティブブリッジ。
//   録音そのものは record プラグインが扱う。ここでは record が持たない
//   「他のアプリが鳴っているか」の問い合わせと、イヤホンの手放しを受け持つ。
enum AudioSessionChannel {
  // Dart 側と一致させるチャンネル名・メソッド名
  static let channelName = "jp.momeo/audio_session"
  static let isOtherAudioPlayingMethod = "isOtherAudioPlaying"
  static let isBluetoothMicInUseMethod = "isBluetoothMicInUse"
  static let releaseBluetoothMicMethod = "releaseBluetoothMic"
  static let releaseAudioSessionMethod = "releaseAudioSession"

  // 通話線（MethodChannel）を1本立て、問い合わせに応える
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case isOtherAudioPlayingMethod:
        result(AVAudioSession.sharedInstance().isOtherAudioPlaying)
      case isBluetoothMicInUseMethod:
        handleIsBluetoothMicInUse(result: result)
      case releaseBluetoothMicMethod:
        handleReleaseBluetoothMic(result: result)
      case releaseAudioSessionMethod:
        handleReleaseAudioSession(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // 今の録音が Bluetooth のマイク（通話用の HFP）を使っているか
  private static func handleIsBluetoothMicInUse(result: FlutterResult) {
    let inputs = AVAudioSession.sharedInstance().currentRoute.inputs
    result(inputs.contains { $0.portType == .bluetoothHFP })
  }

  // 録音を止めずに Bluetooth のマイクを手放し、イヤホンを通話用（HFP）から音楽用（A2DP）に戻す。
  // オプションは Dart 側の _buildRecordConfig(allowsBluetoothMic: false) と揃える。背面では iOS に拒否される
  private static func handleReleaseBluetoothMic(result: FlutterResult) {
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playAndRecord,
        options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP]
      )
      result(nil)
    } catch {
      result(FlutterError(code: "release_bluetooth_mic_failed", message: "\(error)", details: nil))
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
