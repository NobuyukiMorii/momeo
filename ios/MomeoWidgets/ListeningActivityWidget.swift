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
      ListeningActivityView(memoCount: memoCount(of: context))
    } dynamicIsland: { context in
      DynamicIsland {
        // 長押しで開くカード（ロック画面と同じ内容）
        DynamicIslandExpandedRegion(.center) {
          ListeningActivityView(memoCount: memoCount(of: context))
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

  // アプリ側が書いた「このセッションで書き留めたメモの件数」を読む
  private func memoCount(of context: ActivityViewContext<LiveActivitiesAppAttributes>) -> Int {
    return sharedDefault.integer(forKey: context.attributes.prefixedKey("memoCount"))
  }
}

// ---------------------------------
// 表示の中身（momeo のアイコン+文言+件数）
// ---------------------------------
struct ListeningActivityView: View {

  // ---------------------------------
  // 書き留めたメモの件数
  // ---------------------------------
  let memoCount: Int

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
      // 文言と件数
      // ---------------------------------
      VStack(alignment: .leading, spacing: 2) {
        // アプリ名
        Text("momeo")
          .font(.headline)
        // 録音中であることの文言
        Text("音声を認識しています")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        // 件数（0件の間は出さない）
        if memoCount > 0 {
          Text("\(memoCount)件 書き留めました")
            .font(.subheadline)
        }
      }
      Spacer()
    }
    .padding(16)
  }
}
