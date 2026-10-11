import AVFoundation
import Flutter

// 他のアプリの音に録音を合わせるための、AVAudioSession のネイティブブリッジ。
//   録音そのものは record プラグインが扱う。ここでは record が持たない
//   「他のアプリが鳴っているか」の問い合わせ、イヤホンの手放し、機器の抜き差しの知らせを受け持つ。
enum AudioSessionChannel {
  // Dart 側と一致させるチャンネル名・メソッド名
  static let channelName = "jp.momeo/audio_session"
  static let isOtherAudioPlayingMethod = "isOtherAudioPlaying"
  static let isBluetoothMicInUseMethod = "isBluetoothMicInUse"
  static let releaseBluetoothMicMethod = "releaseBluetoothMic"
  static let releaseAudioSessionMethod = "releaseAudioSession"
  static let deviceChangesChannelName = "jp.momeo/audio_session/device_changes"

  // 機器の抜き差しを流す係（購読されている間だけ iOS の知らせを見張る）
  private static let deviceChangeStreamHandler = AudioDeviceChangeStreamHandler()

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

    // 機器の抜き差しを Dart へ流す線（EventChannel）も立てる
    let deviceChanges = FlutterEventChannel(name: deviceChangesChannelName, binaryMessenger: messenger)
    deviceChanges.setStreamHandler(deviceChangeStreamHandler)
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

// ---------------------------------
// イヤホンなどの機器がつながった・外れたことを Dart へ流す
// ---------------------------------
// 機器が変わると録音エンジンが黙って止まることがあるため、Dart 側はこれを合図にすぐ生死を確かめる
final class AudioDeviceChangeStreamHandler: NSObject, FlutterStreamHandler {
  private var observer: NSObjectProtocol?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    observer = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance(),
      queue: .main
    ) { notification in
      let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
      // momeo 自身の設定変更による組み直しは流さず、機器の抜き差しだけを知らせる
      guard reason == .newDeviceAvailable || reason == .oldDeviceUnavailable else { return }
      events(reasonValue)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let observer = observer {
      NotificationCenter.default.removeObserver(observer)
    }
    observer = nil
    return nil
  }
}
