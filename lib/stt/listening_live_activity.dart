import 'dart:async';
import 'dart:io' show Platform;

import 'package:live_activities/live_activities.dart';
import 'package:live_activities/models/live_activity_state.dart';

// ============================================================
// バックグラウンドで録音中であることを示す Live Activity（iOS 専用）
// ============================================================

// ---------------------------------
// クラス本体
// ---------------------------------
class ListeningLiveActivity {

  // App Group の識別子
  static const _appGroupId = 'group.jp.momeo';

  // 8時間の OS 上限より手前で、出し直すまでの時間
  static const _restartInterval = Duration(hours: 7, minutes: 30);

  // Live Activities プラグイン
  static final _plugin = LiveActivities();
  
  // 初期化済みか
  static bool _initialized = false;

  // Live Activity を出しておくべきか（show で立ち、dismiss で下りる）
  static bool _shouldShowActivity = false;

  // 出した Live Activity の識別子（null なら出していない）
  static String? _activityId;

  // バックグラウンド録音の状態が続いている間に書き留めたメモの件数
  static int _memoCount = 0;

  // 出し直しのタイマー
  static Timer? _restartTimer;

  // ---------------------------------
  // 初期設定
  // ---------------------------------
  static Future<void> _initializeOnce() async {
    // 初期化済みなら何もしない
    if (_initialized) return;
    // プラグインを初期化
    await _plugin.init(appGroupId: _appGroupId);
    // 初期化済みに設定
    _initialized = true;
  }

  // ---------------------------------
  // ライブアクティビティを表示
  // ---------------------------------
  static Future<void> show() async {

    // iOS でなければ何もしない
    if (!Platform.isIOS) return;

    // Live Activity を表示するか
    _shouldShowActivity = true;

    // 初期設定
    await _initializeOnce();

    // Live Activity Id が設定されているなら
    if (_activityId != null) {

      // 既存の Live Activity がまだ表示されているなら、何もしない
      if (await _isActivityAlive(_activityId!)) return;

      // 既存の Live Activity が画面から消えている場合、記録を削除
      _restartTimer?.cancel();
      _restartTimer = null;
      _activityId = null;
    }

    // Live Activity が使えない端末・設定なら出さない
    if (!await _plugin.areActivitiesEnabled()) return;

    // 既に_shouldShowActivity が false なら Live Activity を表示しない
    if (!_shouldShowActivity) return;

    // 件数は状態の成立ごとに数え直す
    _memoCount = 0;

    // Live Activity を表示
    _activityId = await _createActivity();

    // 既に_shouldShowActivity が false なら
    if (!_shouldShowActivity) {
      // Live Activity を消す
      await dismiss();
      return;
    }

    // 8時間の OS 上限の手前で、一度終了して出し直す
    _scheduleRestart();
  }

  // ---------------------------------
  // メモの件数をカウントアップ
  // ---------------------------------
  static Future<void> incrementMemoCount() async {
    // iOS でなければ何もしない
    if (!Platform.isIOS) return;
    // Live Activity を表示していなければ何もしない
    final activityId = _activityId;
    // Live Activity Id が設定されていなければ何もしない
    if (activityId == null) return;
    // 件数をカウントアップ
    _memoCount += 1;
    // Live Activity を更新
    await _plugin.updateActivity(activityId, _buildData());
  }

  // ---------------------------------
  // Live Activity を消す
  // ---------------------------------
  static Future<void> dismiss() async {
    // iOS でなければ何もしない
    if (!Platform.isIOS) return;
    // Live Activity を非表示にする
    _shouldShowActivity = false;
    // 再表示予約をキャンセル
    _restartTimer?.cancel();
    _restartTimer = null;
    // Live Activity の記録を取得（_plugin.endActivityの endActivity に利用するため）
    final activityId = _activityId;
    // Live Activity Id を null にする
    _activityId = null;
    // Live Activity Id が設定されていなければ何もしない
    if (activityId == null) return;
    // Live Activity を終了
    await _plugin.endActivity(activityId);
  }

  // ---------------------------------
  // Widget Extension へ渡す表示用の値を作成
  // ---------------------------------
  static Map<String, dynamic> _buildData() => {'memoCount': _memoCount};

  // ---------------------------------
  // Live Activity を8時間の OS 上限の手前で、一度終了して出し直す
  // ---------------------------------
  static void _scheduleRestart() {
    _restartTimer?.cancel();
    _restartTimer = Timer(_restartInterval, () async {
      // 出していなければ何もしない
      final activityId = _activityId;
      if (activityId == null) return;
      // 終了して出し直す
      await _plugin.endActivity(activityId);
      _activityId = await _createActivity();
      // 次の出し直しを予約する
      _scheduleRestart();
    });
  }

  // ---------------------------------
  // Live Activity がアクティブかを確認
  // ---------------------------------
  static Future<bool> _isActivityAlive(String activityId) async {
    final state = await _plugin.getActivityState(activityId);
    return state == LiveActivityState.active;
  }

  // ---------------------------------
  // Live Activity を開始
  // ---------------------------------
  static Future<String?> _createActivity() {
    return _plugin.createActivity(
      'listening', // 値の受け渡しに使う名前
      _buildData(),
      // Push での更新は使わない
      iOSEnableRemoteUpdates: false,
    );
  }
}
