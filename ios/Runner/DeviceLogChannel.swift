import AVFoundation
import Flutter
import os

// 録音の止まり方を後から調べるために、端末ログ（os_log・subsystem "jp.momeo"）へ書き残す窓口。
//   release ビルドの debugPrint は端末ログに残らないため。文字起こしの本文は渡さないので .public で書く
//   Swift 側で起きた出来事は Dart の DeviceLog にも送り、アプリ内のログファイルに同じ時系列で残す
enum DeviceLogChannel {
  // Dart 側と一致させるチャンネル名・メソッド名
  static let channelName = "jp.momeo/device_log"
  static let writeMethod = "write"
  static let writeFromNativeMethod = "writeFromNative"

  // notice は端末に保存される既定のレベル（info・debug は数分で消える）
  private static let logger = Logger(subsystem: "jp.momeo", category: "app")

  // OS からのオーディオの知らせの購読（アプリが生きている間ずっと持つ）
  private static var audioSessionObservers: [NSObjectProtocol] = []

  // Swift 側の出来事を Dart へ送るためのチャンネル
  private static var channel: FlutterMethodChannel?

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case writeMethod:
        write(call.arguments as? String ?? "")
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    observeAudioSession()
  }

  static func write(_ message: String) {
    logger.notice("\(message, privacy: .public)")
  }

  // Swift 側の出来事を書き残す（端末ログに加えて、Dart 経由でアプリ内のログファイルにも残す）
  static func writeFromNative(_ message: String) {
    write(message)
    channel?.invokeMethod(writeFromNativeMethod, arguments: message)
  }

  // ---------------------------------
  // OS からのオーディオの知らせを書き残す
  // ---------------------------------
  // 録音が止まる直前に OS 側で何が起きたかを、Dart の動きと同じ時系列で読めるようにする
  private static func observeAudioSession() {
    guard audioSessionObservers.isEmpty else { return }
    let center = NotificationCenter.default
    let session = AVAudioSession.sharedInstance()

    // 中断の始まり・終わり（電話・Siri・他のアプリなど）
    audioSessionObservers.append(center.addObserver(
      forName: AVAudioSession.interruptionNotification, object: session, queue: .main
    ) { notification in
      let info = notification.userInfo
      let typeValue = info?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
      let reasonValue = info?[AVAudioSessionInterruptionReasonKey] as? UInt ?? 0
      let optionsValue = info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let type = typeValue == AVAudioSession.InterruptionType.began.rawValue ? "began" : "ended"
      writeFromNative("[audioSession] 中断 \(type)（reason=\(reasonValue) options=\(optionsValue)）")
    })

    // 経路の変化（機器の抜き差し・カテゴリの変更など、理由を問わずすべて）
    audioSessionObservers.append(center.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
    ) { notification in
      let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
      let inputs = session.currentRoute.inputs.map { $0.portType.rawValue }.joined(separator: ",")
      writeFromNative("[audioSession] 経路の変化（reason=\(reasonValue) 入力=\(inputs) カテゴリ=\(session.category.rawValue)）")
    })

    // メディアサーバーが落ちた・立ち直った（立ち直っても録音は自動では戻らない）
    audioSessionObservers.append(center.addObserver(
      forName: AVAudioSession.mediaServicesWereLostNotification, object: session, queue: .main
    ) { _ in
      writeFromNative("[audioSession] メディアサーバーが落ちました")
    })
    audioSessionObservers.append(center.addObserver(
      forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main
    ) { _ in
      writeFromNative("[audioSession] メディアサーバーが立ち直りました")
    })
  }
}
