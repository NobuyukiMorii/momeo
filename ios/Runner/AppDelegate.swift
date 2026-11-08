import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // リスニング画面のメモ一覧（OS の文字選択を使う UITextView）を、Flutter の画面に埋め込めるようにする
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeMemoList") {
      registrar.register(NativeMemoListFactory(messenger: registrar.messenger()),
                         withId: NativeMemoListFactory.viewType)
    }

    // OS 内蔵の文字起こし（SpeechTranscriber）を Dart から使うネイティブブリッジを登録
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SpeechTranscriberChannel") {
      SpeechTranscriberChannel.register(with: registrar.messenger())
    }

    // 他のアプリの音に録音を合わせるための AVAudioSession の窓口を登録
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AudioSessionChannel") {
      AudioSessionChannel.register(with: registrar.messenger())
    }

    // 録音の止まり方を後から調べるための、端末ログ（os_log）への窓口を登録
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceLogChannel") {
      DeviceLogChannel.register(with: registrar.messenger())
    }
  }
}
