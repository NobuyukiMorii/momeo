# バックグラウンド録音 — 検証に使った実装

`ios.md` / `android.md` の実機検証で実際に動かした実装の全文。**検証後に作業ツリーから破棄した**ため、コードは残っていない。実装に着手するときの出発点として、そのまま再現できる形で記録する。

## この実装をそのまま出せない理由

**バックグラウンド録音が常時ONで、ユーザーが止める手段がない。** 検証のために最短経路で組んだもので、`store_policy.md` の実装要件を満たしていない。

- 設定での ON / OFF がない（Apple 5.1.1(ii) の「同意を撤回する手段」に抵触する）
- 開示＋同意画面がない（Play の prominent disclosure 要件を満たさない）
- 常駐通知に停止ボタンがない
- 常駐通知の重要度が既定のままで、通知欄の「サイレント」欄に入る
- iOS 側に録音中を示す表示がない（Live Activity・ローカル通知いずれも未実装）

中断復帰の設定（`RecordConfig` の `audioInterruption` ほか）だけは独立した不具合修正として本体に取り込み済みなので、以下には含めない。

---

## 1. パッケージ

```yaml
# pubspec.yaml
dependencies:
  flutter_foreground_task: ^10.0.0
```

検証時の解決バージョンは 10.0.0。

---

## 2. iOS — Info.plist

`ios/Runner/Info.plist` に追加する。`UIApplicationSupportsIndirectInputEvents` の直後に置いた。

```xml
<key>UIBackgroundModes</key>
<array>
	<string>audio</string>
</array>
```

iOS 側の変更はこれだけ。`record` のサンプルにある `fetch` は入れていないが、それで成立した。

---

## 3. Android — AndroidManifest.xml

`android/app/src/main/AndroidManifest.xml` の `<manifest>` 直下に追加する。

```xml
<!-- 背面で録音を続けるためのフォアグラウンドサービス（常駐通知が出る） -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE"/>
```

`<application>` の中、`<activity>` と `flutterEmbedding` の `<meta-data>` の間に追加する。

```xml
<!-- flutter_foreground_task のサービス本体。クラス名は変更不可 -->
<service
    android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
    android:foregroundServiceType="microphone"
    android:exported="false" />
```

---

## 4. Android — 常駐サービスの部品

`lib/stt/listening_foreground_service.dart` として新規に置いた全文。

```dart
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
//   SttListeningPipeline が行う（TaskHandler は使わない）。
//
//   iOS は UIBackgroundModes の audio だけで背面録音が成立するため、
//   このサービスは動かさない。
// ============================================================

class ListeningForegroundService {
  // 通知チャンネルとサービスの識別子
  static const _channelId = 'momeo_listening';
  static const _serviceId = 1000;

  static bool _initialized = false;

  // ---------------------------------
  // サービスの開始（録音の開始と同時に呼ぶ）
  //   Android 13 以降は通知許可がないと常駐通知を出せないため、先に要求する
  // ---------------------------------
  static Future<void> start() async {
    if (!Platform.isAndroid) return;

    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    _initializeOnce();

    if (await FlutterForegroundTask.isRunningService) return;

    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: [ForegroundServiceTypes.microphone],
      notificationTitle: 'momeo',
      notificationText: '声を聞いています',
    );
    if (result is ServiceRequestFailure) {
      debugPrint('[fgService] 常駐サービスを開始できませんでした: ${result.error}');
    }
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
```

---

## 5. パイプラインへの接続

`lib/stt/stt_listening_pipeline.dart` に3箇所を足した。

import を追加する。

```dart
import 'package:momeo/stt/listening_foreground_service.dart';
```

`start()` の中、マイク権限の確認の直後、`_vad.clear()` の前に置く。**録音を始める前にサービスを立てる**ことが重要で、順序を逆にすると背面遷移時にマイクを切られる。

```dart
    // Android は常駐サービスを立ててからでないと、背面に回った時点でマイクを切られる
    await ListeningForegroundService.start();
```

`stop()` の末尾、`_drainAndTranscribe()` の後に置く。

```dart
    // 録音を止めたら常駐サービスも畳む（通知を出しっぱなしにしない）
    await ListeningForegroundService.stop();
```

---

## 実装に着手するときの注意

上記をそのまま戻すだけでは足りない。`store_policy.md` の実装要件を満たす形にするには、少なくとも次が必要になる。

1. 設定でのON/OFF（初期値OFF）と、その状態に応じたサービスの起動・停止
2. ONにするタイミングの開示＋同意画面（マイク権限のリクエストより前）
3. 常駐通知への停止ボタン（`FlutterForegroundTask.startService` の `notificationButtons`）
4. 常駐通知の重要度の引き上げ（`AndroidNotificationOptions` のチャンネル設定）
5. iOS の録音中表示（Live Activity かローカル通知）

現状の `SttListeningPipeline.start()` / `stop()` にサービスの起動を直結させている構造は、「録音するなら常にバックグラウンド対応」を意味する。ON/OFF を入れるなら、この結線自体を見直すことになる。
