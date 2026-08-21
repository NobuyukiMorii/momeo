import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ============================================================
// ListeningBackgroundNotice — 背面で録音中であることを示すローカル通知（iOS 専用）
//
//   Apple 2.5.14 は録音中の明確な視覚表示を求める。Android は常駐通知が
//   OS 側で強制されるため、この部品は iOS でだけ動く。
//   背面に入ったときに1回出し、前面に戻ったら消す。
// ============================================================

class ListeningBackgroundNotice {
  // 通知の識別子（消すときに同じ番号を指定する）
  static const _notificationId = 2000;

  // 背面遷移の瞬間は iOS がまだアプリを前面扱いにしていて、その間に出した
  // 通知は表示されずに終わる。確実に背面扱いへ切り替わるまで待つ時間
  static const _showDelay = Duration(seconds: 1);

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // 通知を出したい状態か（待っている間に前面へ戻ったら取り下げる）
  static bool _wantsNotice = false;

  // 初期設定。通知許可は設定を ON にする流れで取得済みのため、ここでは要求しない
  static Future<void> _initializeOnce() async {
    if (_initialized) return;

    const settings = InitializationSettings(
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  // ---------------------------------
  // 背面に入ったときに出す
  // ---------------------------------
  static Future<void> show() async {
    if (!Platform.isIOS) return;

    _wantsNotice = true;
    await _initializeOnce();

    // 前面扱いが解けるのを待ってから出す。待つ間に前面へ戻っていたら出さない
    await Future<void>.delayed(_showDelay);
    if (!_wantsNotice) return;

    // 万一まだ前面扱いだった場合の保険として、前面での表示方法も明示する
    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentBanner: true,
        presentList: true,
        presentSound: false,
      ),
    );
    await _plugin.show(
      id: _notificationId,
      title: 'momeo',
      body: '声を聞いています',
      notificationDetails: details,
    );
  }

  // ---------------------------------
  // 前面に戻ったときに消す
  // ---------------------------------
  static Future<void> dismiss() async {
    if (!Platform.isIOS) return;

    _wantsNotice = false;
    if (!_initialized) return;

    await _plugin.cancel(id: _notificationId);
  }
}
