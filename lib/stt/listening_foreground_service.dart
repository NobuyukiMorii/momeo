import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// ============================================================
// ListeningForegroundService — 背面で録音を続けるための常駐サービス（Android 専用）
//
//   Android は 9 以降、背面のアプリからマイクを触れない。継続するには
//   microphone タイプのフォアグラウンドサービスを動かし、常駐通知を出す
//   必要がある（通知は OS が描く。アプリの画面とは別物）。
//
//   ここではサービスを「録音し続ける権利と常駐通知」としてだけ使い、
//   録音・VAD・文字化は今まで通りメインアイソレートの
//   SttListeningPipeline が行う。
//
//   通知の停止ボタンの押下だけは TaskHandler（別アイソレート）にしか
//   届かないため、押下をメインアイソレートへ転送する最小のハンドラーを持つ。
//   受け取る側は main() の initCommunicationPort() と
//   FlutterForegroundTask.addTaskDataCallback() で結線する。
//
//   iOS は UIBackgroundModes の audio だけで背面録音が成立するため、
//   このサービスは動かさない。
// ============================================================

// 停止ボタンの押下をメインアイソレートへ伝えるメッセージ
const listeningServiceStopRequested = 'listeningServiceStopRequested';

// 常駐通知に置く停止ボタンの識別子
const _stopButtonId = 'stop_listening';

class ListeningForegroundService {
  // 通知チャンネルとサービスの識別子
  static const _channelId = 'momeo_listening';
  static const _serviceId = 1000;

  static bool _initialized = false;

  // ---------------------------------
  // サービスの開始（録音を始める前に呼ぶ。起動できたかを返す）
  //   通知許可の確認は呼び出し側の担当（listening_providers.dart）
  // ---------------------------------
  static Future<bool> start() async {
    if (!Platform.isAndroid) return false;

    _initializeOnce();

    if (await FlutterForegroundTask.isRunningService) return true;

    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: [ForegroundServiceTypes.microphone],
      notificationTitle: 'momeo',
      notificationText: '声を聞いています',
      notificationButtons: [
        const NotificationButton(id: _stopButtonId, text: '録音を停止'),
      ],
      callback: startListeningServiceCallback,
    );
    if (result is ServiceRequestFailure) {
      debugPrint('[fgService] 常駐サービスを開始できませんでした: ${result.error}');
      return false;
    }
    return true;
  }

  // ---------------------------------
  // サービスの停止（録音の停止と同時に呼ぶ）
  // ---------------------------------
  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (!await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.stopService();
  }

  // 通知チャンネルなどの初期設定。二重に呼んでも害はないが一度で足りる
  static void _initializeOnce() {
    if (_initialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: '録音中の通知',
        channelDescription: '背面で声を聞いている間、表示され続けます',
        // 既定の LOW だと通知欄の「サイレント」欄に入るため、通常欄に出す
        channelImportance: NotificationChannelImportance.DEFAULT,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // 録音はメインアイソレート側で行うため、サービス側の定期実行は使わない
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
      ),
    );
    _initialized = true;
  }
}

// ---------------------------------
// 通知ボタンの受け口（別アイソレートで動く）
//   録音には関与しない。停止ボタンの押下をメインアイソレートへ転送するだけ
// ---------------------------------
@pragma('vm:entry-point')
void startListeningServiceCallback() {
  FlutterForegroundTask.setTaskHandler(_ListeningServiceHandler());
}

class _ListeningServiceHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == _stopButtonId) {
      FlutterForegroundTask.sendDataToMain(listeningServiceStopRequested);
    }
  }
}
