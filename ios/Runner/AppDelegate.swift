import ActivityKit
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

    // STT モデルの実パスを Dart に返すネイティブブリッジを登録
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SttModelChannel") {
      SttModelChannel.register(with: registrar.messenger())
    }
  }

  // ---------------------------------
  // アプリスイッチャーから終了されたときに「録音中」の Live Activity を消す
  // ---------------------------------
  // Dart 側の dismiss はプロセスごと止まるので走らない。iOS が終了前にくれる数秒のうちに、ここで消す
  override func applicationWillTerminate(_ application: UIApplication) {
    // --- iOS 16.1 以降の場合のみ
    if #available(iOS 16.1, *) {
      // --- Live Activity の終了処理を実行
      endAllListeningActivities()
    }
    // --- スーパークラスの終了処理を実行
    super.applicationWillTerminate(application)
  }

  // ---------------------------------
  // Live Activity の終了
  // ---------------------------------
  @available(iOS 16.1, *)
  private func endAllListeningActivities() {
    // --- 終了処理が終わるまで待つためのセマフォを作る
    let semaphore = DispatchSemaphore(value: 0)
    // --- 終了処理を別スレッドで走らせる
    Task.detached {
      // --- Live Activity を一つずつループ
      for activity in Activity<LiveActivitiesAppAttributes>.activities {
        // --- Live Activity を終了する
        await activity.end(dismissalPolicy: .immediate)
      }
      // --- 終了処理が終わったらセマフォを解放する
      semaphore.signal()
    }
    // --- 終了処理が終わるまで待つ
    _ = semaphore.wait(timeout: .now() + 3.0)
  }
}

// ---------------------------------
// Live Activity の属性定義
// ---------------------------------
struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
  public typealias LiveDeliveryData = ContentState

  public struct ContentState: Codable, Hashable {
    var appGroupId: String
  }

  var id = UUID()
}
