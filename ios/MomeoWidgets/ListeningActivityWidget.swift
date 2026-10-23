import ActivityKit
import SwiftUI
import WidgetKit

// ---------------------------------
// Live Activity の属性定義
// ---------------------------------
struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {

  // live_activities パッケージが参照する別名（変更不可）
  public typealias LiveDeliveryData = ContentState

  // ---------------------------------
  // 更新のたびに渡される状態（実データは UserDefaults で受け渡すため、これだけ）
  // ---------------------------------
  public struct ContentState: Codable, Hashable {
    // アプリ側と共有する App Group の識別子
    var appGroupId: String
  }

  var id = UUID()
}

// ---------------------------------
// アプリ側が書いた値を読むためのキー（Live Activity の id が接頭辞になる決まり）
// ---------------------------------
extension LiveActivitiesAppAttributes {
  func prefixedKey(_ key: String) -> String {
    return "\(id)_\(key)"
  }
}

// アプリ側と値を受け渡す App Group
private let sharedDefault = UserDefaults(suiteName: "group.jp.momeo")!

// ---------------------------------
// Live Activity 本体
// ---------------------------------
struct ListeningActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
      // ロック画面
      ListeningActivityView(recording: recording(of: context))
    } dynamicIsland: { context in
      DynamicIsland {
        // 長押しで開くカード（ロック画面と同じ内容）
        DynamicIslandExpandedRegion(.center) {
          ListeningActivityView(recording: recording(of: context))
        }
      } compactLeading: {
        // 常時見える小さい表示
        Image(systemName: "mic.fill")
      } compactTrailing: {
        EmptyView()
      } minimal: {
        // ほかの Live Activity と同居したときの最小表示
        Image(systemName: "mic.fill")
      }
    }
  }

  // アプリ側が書いた「録音を始めた時刻」（1970年からの秒数）と「中断しているか」を読む
  private func recording(of context: ActivityViewContext<LiveActivitiesAppAttributes>) -> RecordingStatus {
    let startedAt = sharedDefault.double(forKey: context.attributes.prefixedKey("recordingStartedAt"))
    let isPaused = sharedDefault.bool(forKey: context.attributes.prefixedKey("isRecordingPaused"))
    return RecordingStatus(startedAt: Date(timeIntervalSince1970: startedAt), isPaused: isPaused)
  }
}

// ---------------------------------
// 録音の状態（表示に使う値）
// ---------------------------------
struct RecordingStatus {
  // 録音画面で録音を始めた時刻（経過時間の起点）
  let startedAt: Date
  // 録音が一時的に中断されているか（他のアプリが鳴っている・OS に中断されている）
  let isPaused: Bool
}

// ---------------------------------
// 表示の中身（momeo のアイコン+文言+経過時間）
// ---------------------------------
struct ListeningActivityView: View {

  // ---------------------------------
  // 録音の状態
  // ---------------------------------
  let recording: RecordingStatus

  // ---------------------------------
  // 組み立て
  // ---------------------------------
  var body: some View {
    HStack(spacing: 12) {
      // ---------------------------------
      // momeo のアイコン
      // ---------------------------------
      Image("MomeoIcon")
        .resizable()
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 8))
      // ---------------------------------
      // 文言と経過時間
      // ---------------------------------
      VStack(alignment: .leading, spacing: 2) {
        // アプリ名
        Text("momeo")
          .font(.headline)
        // 今の録音の状態を表す文言
        Text(recording.isPaused ? "録音が一時的に中断されています" : "音声を認識しています")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        // 録音を始めてからの時間（OS が1秒ごとに進める。中断中も止めない）
        Text(recording.startedAt, style: .timer)
          .font(.subheadline)
          .monospacedDigit()
      }
      Spacer()
    }
    .padding(16)
  }
}
