import SwiftUI
import WidgetKit

// ============================================================
// Widget Extension の入口（ここに並べた Widget が OS に登録される）
// ============================================================

@main
struct MomeoWidgetsBundle: WidgetBundle {
  var body: some Widget {
    ListeningActivityWidget()
  }
}
