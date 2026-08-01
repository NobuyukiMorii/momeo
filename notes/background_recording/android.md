# バックグラウンド録音 — Android

概要と両OS共通の制約は `overview.md` を参照。

---

## 必要な対応

Android 9 以降、**背面のアプリはマイクにアクセスできない**。継続するには `microphone` タイプのフォアグラウンドサービス（常駐通知が出る）が必須になる。`record` 単体では実現できず、公式ドキュメントも「外部パッケージを使え」とだけ書いている。ここでは `flutter_foreground_task` を使う。

1. `FOREGROUND_SERVICE` と `FOREGROUND_SERVICE_MICROPHONE` パーミッションの宣言
2. サービスに `android:foregroundServiceType="microphone"` を指定
3. `startForeground()` を `FOREGROUND_SERVICE_TYPE_MICROPHONE` で呼ぶ（パッケージが行う）
4. `RECORD_AUDIO` の実行時許可が取れた状態であること
5. Android 13 以降は `POST_NOTIFICATIONS` の実行時許可も必要。拒否されてもサービス自体は動くが常駐通知が表示されないため、Play が求める「ユーザーが実行を認識できる状態」を満たせなくなる

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE"/>

<!-- flutter_foreground_task のサービス本体。クラス名は変更不可 -->
<service
    android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
    android:foregroundServiceType="microphone"
    android:exported="false" />
```

`FOREGROUND_SERVICE` と `POST_NOTIFICATIONS` はパッケージ側の manifest でも宣言されておりマージされるが、依存パッケージの都合に暗黙で乗らないよう、マイク関連はアプリ側で明示する。

---

## サービスの位置づけ

**サービスは「録音し続ける権利と常駐通知」としてだけ使う。** 録音・VAD・文字化は従来どおりメインアイソレートの `SttListeningPipeline` が行う。

`flutter_foreground_task` は別アイソレートで動く `TaskHandler` を持てるが、**使っていない**（`startService` の `callback` は省略可）。実機検証で「メインアイソレートのまま背面で動く」ことが確認できたため、パイプラインを別アイソレートへ移植する必要がない。

実装は `lib/stt/listening_foreground_service.dart` に閉じており、`SttListeningPipeline.start()` / `stop()` から呼ぶ。iOS では何もしない。

---

## 実機検証（2026-08-01）

**条件**: Pixel 8a / Android 16（API 36、targetSdk 36）/ **debug ビルド**。

iOS と違い debug ビルドで検証している。Android には「デバッガ接続が背面停止を抑止する」仕組みがなく、背面のマイク制限もフォアグラウンドサービスの要件も**デバッグ可能かどうかとは無関係に OS が課す**ため、debug でも結果は変わらない。加えて、開発用のモデル手置き（`scripts/place_android_device_models.sh`）が `run-as` に依存しており、release ビルドではモデルを配置できないという事情もある。

判定には端末の `dumpsys` と `adb logcat` を使った。

**結果**

| 確認項目 | 結果 |
|---|---|
| `microphone` 型でサービスが起動するか | 起動する（`types=0x00000080`） |
| Android 16 の権限チェックを通過するか | 通過する |
| 常駐通知が登録されるか | される（`ONGOING_EVENT｜NO_CLEAR｜FOREGROUND_SERVICE`） |
| 背面での録音の継続 | 続く（背面遷移後もチャンク受信が途切れない） |
| 背面での文字化とメモ保存 | 動く（背面での発話がメモとして残る） |

サービスの状態は次のように確認できる。

```bash
adb shell dumpsys activity services jp.momeo
```

```
isForeground=true  foregroundId=1000  types=0x00000080
foregroundNoti=Notification(channel=momeo_listening
  flags=ONGOING_EVENT|ONLY_ALERT_ONCE|NO_CLEAR|FOREGROUND_SERVICE)
```

`types=0x00000080` が `FOREGROUND_SERVICE_TYPE_MICROPHONE` にあたる。

**分かったこと**

- 録音と推論を別アイソレートへ引っ越す必要は**ない**。`TaskHandler` なしで背面動作が成立する
- 常駐通知の重要度が `importance=2`（LOW）のため、**通知欄の「サイレント」欄に入る**。音もポップアップも出ないので、ホーム画面を見ているだけでは気づけない。Play の「ユーザーが実行を認識できること」という原則に照らすと、通常欄に出す方が安全。チャンネルの重要度で調整できる

**未検証**

- 長時間（数時間規模）の連続動作とバッテリー消費
- 通知許可を拒否した場合の挙動
- 通知からの停止操作（未実装）
- OEM 独自のプロセスキル（Pixel 以外の端末）

---

## Android 固有の注意

**常駐通知は消せない前提ではない**

Android 13 以降、ユーザーはフォアグラウンドサービスの通知をスワイプで消せる。ただし**通知を消してもサービスは動き続ける**ため、「通知を消す＝停止」ではない。停止手段は通知内のボタンとして別途用意する必要がある。

システム設定側にも実行中のアプリを一覧して強制停止できる画面があり、そこから止められるとアプリは正常な終了処理を行えない。

**タイムアウトの対象外**

Android 15 の6時間タイムアウトは `dataSync` と `mediaProcessing` が対象で、`microphone` は含まれない（→ `overview.md`）。
