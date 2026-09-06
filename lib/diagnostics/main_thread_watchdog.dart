import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;

// ============================================================
// メインスレッドが止まっていないか見張る（ANR の手前で気づくための仕掛け）
//
//   一定間隔で自分を呼び直し、予定時刻からの遅れを測る。遅れは
//   そのままメインスレッドが他の仕事をできなかった時間になる。
//   閾値を超えたぶんだけ記録し、Console の「メインスレッド」で読める。
// ============================================================

// 見張りの間隔。短くしすぎると測定自体が負荷になる
const _kInterval = Duration(milliseconds: 500);

// これを超える遅れを「詰まった」とみなす。Android の ANR は 5秒
const _kStallThreshold = Duration(milliseconds: 700);

// 覚えておく件数の上限（古いものから捨てる）
const _kMaxRecords = 50;

// 詰まりの記録1件
class MainThreadStall {
  const MainThreadStall({required this.at, required this.duration});

  final DateTime at;
  final Duration duration;
}

class MainThreadWatchdog {
  MainThreadWatchdog._();

  static final MainThreadWatchdog instance = MainThreadWatchdog._();

  // 新しい順の記録。Console のセクションがそのまま購読する
  final ValueNotifier<List<MainThreadStall>> stalls =
      ValueNotifier<List<MainThreadStall>>(const []);

  Timer? _timer;
  DateTime _expectedAt = DateTime.now();

  void start() {
    if (_timer != null) return;
    _scheduleNext();
  }

  void _scheduleNext() {
    _expectedAt = DateTime.now().add(_kInterval);
    _timer = Timer(_kInterval, _onTick);
  }

  void _onTick() {
    final delay = DateTime.now().difference(_expectedAt);

    // バックグラウンドではタイマー自体が間引かれるため、詰まりと区別できない
    if (delay >= _kStallThreshold && _isForeground) {
      _record(delay);
    }
    _scheduleNext();
  }

  bool get _isForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  // リリースビルドでも残るよう、kDebugMode で囲まずに出す
  void _record(Duration delay) {
    debugPrint('[watchdog] メインスレッドが ${delay.inMilliseconds}ms 止まりました');

    final updated = [
      MainThreadStall(at: DateTime.now(), duration: delay),
      ...stalls.value,
    ];
    stalls.value =
        updated.length <= _kMaxRecords ? updated : updated.sublist(0, _kMaxRecords);
  }
}
