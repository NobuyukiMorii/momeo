import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// ============================================================
// ListeningForegroundService — バックグラウンドで録音を続けるためのフォアグラウンドサービス（Android 専用）
//
//   Android は 9 以降、バックグラウンドのアプリからマイクを触れない。継続するには
//   microphone タイプのフォアグラウンドサービスを動かし、常駐通知を出す
//   必要がある（通知は OS が描く。アプリの画面とは別物）。
//
//   ここではフォアグラウンドサービスを「録音し続ける権利と常駐通知」としてだけ使い、
//   録音・VAD・文字化は今まで通りメインアイソレートの
//   SttListeningPipeline が行う（TaskHandler は使わない）。
//
//   iOS は UIBackgroundModes の audio だけでバックグラウンド録音が成立するため、
//   このフォアグラウンドサービスは動かさない。
// ============================================================

class ListeningForegroundService {
  // 通知チャンネルとフォアグラウンドサービスの識別子
  static const _channelId = 'momeo_listening';
  static const _serviceId = 1000;

  static bool _initialized = false;

  // ---------------------------------
  // フォアグラウンドサービスの開始
  // ---------------------------------
  static Future<bool> start() async {
    // Android でなければ何もしない
    if (!Platform.isAndroid) return false;

    // 通知許可を取得
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    // 通知が許可されていなければ
    if (permission != NotificationPermission.granted) {
      // 許可を要求
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // フォアグラウンドサービスを初期化
    _initializeOnce();

    // フォアグラウンドサービスが既に起動している場合は何もしない
    if (await FlutterForegroundTask.isRunningService) return true;

    // フォアグラウンドサービスを起動
    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: [ForegroundServiceTypes.microphone],
      notificationTitle: 'momeo',
      notificationText: '声を聞いています',
    );
    // フォアグラウンドサービスの起動に失敗
    if (result is ServiceRequestFailure) {
      debugPrint('[fgService] フォアグラウンドサービスを開始できませんでした: ${result.error}');
      return false;
    }
    // フォアグラウンドサービスの起動に成功
    return true;
  }

  // ---------------------------------
  // フォアグラウンドサービスの停止
  // ---------------------------------
  static Future<void> stop() async {
    // Android でなければ何もしない
    if (!Platform.isAndroid) return;
    // フォアグラウンドサービスが起動していなければ何もしない
    if (!await FlutterForegroundTask.isRunningService) return;
    // フォアグラウンドサービスを停止
    await FlutterForegroundTask.stopService();
  }

  // 通知チャンネルなどの初期設定。二重に呼んでも害はないが一度で足りる
  static void _initializeOnce() {
    // 既に初期化されていれば何もしない
    if (_initialized) return;

    // フォアグラウンドサービスを初期化
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: '録音中の通知',
        channelDescription: 'バックグラウンドで声を聞いている間、表示され続けます',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // 録音はメインアイソレート側で行うため、フォアグラウンドサービス側の定期実行は使わない
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
      ),
    );
    
    // 初期化完了
    _initialized = true;
  }
}
