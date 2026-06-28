import 'dart:io' show Platform;

import 'package:flutter/services.dart';

// ============================================================
// Play Asset Delivery（Android の「アセットパック自動DL」）を Dart から扱う窓口。
//
//   パック名を1つ受け取り、そのパックについて
//     - 取得完了後の実パス
//     - 今の状態（未開始／DL中／完了／失敗）と進捗
//     - 取得開始・再試行
//   を提供する。Android ネイティブの橋渡し（AssetPackDeliveryChannel.kt）を呼ぶ。
//
//   この窓口は特定のモデルを知らない（パック名で動く汎用部品）。
//   Android 以外には自動DLの仕組みが無いため、常に「完了」を返す安全な空実装になる。
//
//   ※ チャンネル名・メソッド名・辞書のキーは、ネイティブ側（AssetPackDeliveryChannel.kt）と
//     必ず一致させること。
// ============================================================

// ---------------------------------
// 準備フェーズ（Android の細かい状態を、扱いやすい4つに集約したもの）
// ---------------------------------

enum AssetPackPhase {
  notStarted, // まだ取得していない（未到着）
  downloading, // 取得中
  completed, // 取得完了（実パスが使える）
  failed, // 失敗（再試行が必要）
}

// ---------------------------------
// アセットパックの今の状態（フェーズ＋進捗）
// ---------------------------------

class AssetPackState {
  const AssetPackState({
    required this.phase,
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.errorCode,
    this.rawStatus,
  });

  final AssetPackPhase phase;
  final int bytesDownloaded; // ここまでに落ちたバイト数
  final int totalBytes; // 総バイト数（不明なら 0）
  final int errorCode; // 失敗時のエラーコード（無ければ 0）
  final String? rawStatus; // Android の元の状態名（waitingForWifi 等。表示の補助用）

  // 0.0〜1.0 の進捗。総量が不明（0）なら null。
  double? get progress {
    if (totalBytes <= 0) return null;
    return (bytesDownloaded / totalBytes).clamp(0.0, 1.0);
  }

  // Android 以外、またはパックが無いときに使う「完了扱い」の既定値。
  static const AssetPackState ready = AssetPackState(
    phase: AssetPackPhase.completed,
    bytesDownloaded: 0,
    totalBytes: 0,
    errorCode: 0,
  );

  // まだ取得していない（未到着）の既定値。
  static const AssetPackState notStarted = AssetPackState(
    phase: AssetPackPhase.notStarted,
    bytesDownloaded: 0,
    totalBytes: 0,
    errorCode: 0,
  );

  // ネイティブから受け取った辞書を状態に変換する。
  factory AssetPackState.fromMap(Map<dynamic, dynamic> map) {
    final status = map['status'] as String?;
    return AssetPackState(
      phase: _phaseFromStatus(status),
      bytesDownloaded: (map['bytesDownloaded'] as num?)?.toInt() ?? 0,
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      errorCode: (map['errorCode'] as num?)?.toInt() ?? 0,
      rawStatus: status,
    );
  }
}

// Android の状態名を、4つのフェーズに振り分ける。
AssetPackPhase _phaseFromStatus(String? status) {
  switch (status) {
    case 'pending':
    case 'downloading':
    case 'transferring':
    case 'waitingForWifi':
      return AssetPackPhase.downloading;
    case 'completed':
      return AssetPackPhase.completed;
    case 'failed':
      return AssetPackPhase.failed;
    // notInstalled / canceled / unknown / null は「未到着」として扱う（取得し直せる）。
    default:
      return AssetPackPhase.notStarted;
  }
}

// ---------------------------------
// 配信の窓口（パック名ごとに1つ作る）
// ---------------------------------

class AssetPackDelivery {
  AssetPackDelivery(this.packName);

  final String packName;

  // ネイティブ側と対のチャンネル。
  static const MethodChannel _method = MethodChannel('jp.momeo/asset_pack');
  static const EventChannel _events = EventChannel('jp.momeo/asset_pack/events');

  static const String _argPackName = 'packName';

  // 取得完了後の実パス。まだ無ければ null。
  Future<String?> assetsPath() async {
    if (!Platform.isAndroid) return null;
    return _method.invokeMethod<String>('getAssetsPath', {_argPackName: packName});
  }

  // 今の状態を1回だけ取得。パックが無ければ「未到着」を返す。
  Future<AssetPackState> currentState() async {
    if (!Platform.isAndroid) return AssetPackState.ready;
    final map = await _method.invokeMapMethod<String, dynamic>(
      'getState',
      {_argPackName: packName},
    );
    if (map == null) return AssetPackState.notStarted;
    return AssetPackState.fromMap(map);
  }

  // DL状態が変わるたびに流れてくるストリーム（このパックのぶんだけ）。
  Stream<AssetPackState> watchState() {
    if (!Platform.isAndroid) {
      return Stream<AssetPackState>.value(AssetPackState.ready);
    }
    return _events
        .receiveBroadcastStream()
        // 通知は全パック分が流れてくるので、このパックのものだけ通す。
        .where((event) => event is Map && event['packName'] == packName)
        .map((event) => AssetPackState.fromMap(event as Map<dynamic, dynamic>));
  }

  // 取得開始・再試行。未到着や失敗のときに呼ぶ。
  Future<void> fetch() async {
    if (!Platform.isAndroid) return;
    await _method.invokeMethod<void>('fetch', {_argPackName: packName});
  }
}
