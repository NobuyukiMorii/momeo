import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// ============================================================
// バックグラウンドで録音を続けるためのフォアグラウンドサービス（Android 専用）
// ============================================================

// 停止ボタンの押下をアプリ本体へ伝えるメッセージ
const listeningServiceStopRequested = 'listeningServiceStopRequested';

// 常駐通知に置く停止ボタンの識別子
const _stopButtonId = 'stop_listening';

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

    // 通知の許可を確認（許可の要求は設定を ON にする操作の中で済ませている）
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    // 許可が無ければ起動しない（後から OS 設定で取り消されたケース。フォアグラウンドだけの録音に落ちる）
    if (permission != NotificationPermission.granted) {
      debugPrint('[fgService] 通知が許可されていないため、フォアグラウンドサービスを起動しません');
      return false;
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
      notificationText: '音声を認識しています',
      // 常駐通知に停止ボタンを置く（押下は下の _ListeningServiceHandler 経由でアプリ本体に届く）
      notificationButtons: [
        const NotificationButton(id: _stopButtonId, text: 'バックグラウンド録音を停止'),
      ],
      callback: startListeningServiceCallback,
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
        channelDescription: 'バックグラウンドで音声を認識している間、表示され続けます',
        // 既定の LOW だと通知欄の「サイレント」欄に入るため、通常欄に出す
        channelImportance: NotificationChannelImportance.DEFAULT,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // 録音はアプリ本体側で行うため、フォアグラウンドサービス側の定期実行は使わない
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
      ),
    );
    
    // 初期化完了
    _initialized = true;
  }
}

// ---------------------------------
// 常駐通知の停止ボタンの押下をアプリ本体へ知らせる
// （押下は Android の仕様でここにしか届かない。録音を止める処理は受け取った本体側がやる）
// ---------------------------------
@pragma('vm:entry-point')
void startListeningServiceCallback() {
  // フォアグラウンドサービスのハンドラーを設定
  FlutterForegroundTask.setTaskHandler(_ListeningServiceHandler());
}

// ---------------------------------
// フォアグラウンドサービスのハンドラー
// ---------------------------------
class _ListeningServiceHandler extends TaskHandler {

  // フォアグラウンドサービスが起動した時
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  // フォアグラウンドサービスが繰り返し実行された時
  @override
  void onRepeatEvent(DateTime timestamp) {}

  // フォアグラウンドサービスが終了した時
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  // 停止ボタンが押されたらアプリ本体へ知らせる
  @override
  void onNotificationButtonPressed(String id) {
    if (id == _stopButtonId) { // 停止ボタンが押されたら
      // アプリ本体へ知らせる
      FlutterForegroundTask.sendDataToMain(listeningServiceStopRequested);
    }
  }
}
