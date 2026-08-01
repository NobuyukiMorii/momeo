# バックグラウンド録音 — iOS

概要と両OS共通の制約は `overview.md` を参照。

---

## 必要な対応

`record` パッケージだけで完結する。追加パッケージは不要。

1. `Info.plist` に `UIBackgroundModes` を追加する（Xcode の Capabilities で Background Modes → Audio を ON にすると同じ内容が書き込まれるので、実質1手順）
2. `AVAudioSession` のカテゴリを `record` または `playAndRecord` にして、セッションをアクティブに保つ
3. `RecordConfig` で中断時の挙動を指定する（既定のままだと中断後に復帰しない。後述）

```xml
<key>UIBackgroundModes</key>
<array>
	<string>audio</string>
</array>
```

`record` のサンプルは `audio` に加えて `fetch` も配列に入れているが、**実機検証では `audio` のみで成立した**。

Apple 公式の記述としては、アーカイブ済みの Audio Session Programming Guide に録音アプリ向けの指示として次の一文がある。ただし2017年更新の廃止済みドキュメントなので、一次情報としては `record` のドキュメントと現行の Info.plist キーリファレンスを優先する。

> "Ensure that the audio `UIBackgroundModes` flag is set."

---

## 中断からの復帰

`record` の `audioInterruption` の既定値は `AudioInterruptionMode.pause`（自動停止・**手動再開**）である。再開処理を書かない限り、着信や他アプリのマイク奪取で一度止まったらそのまま戻らない。

これは背面に限らず**前面でも同じ**で、対処しなければ通話後にリスニングが死んだままになる。**現行アプリに存在する不具合**であり、バックグラウンド録音を入れるかどうかとは独立に修正の価値がある。

`pauseResume` に変え、`mixWithOthers` を併用すると、**背面のままでも自動的に録音が再開する**（実機検証済み）。バックグラウンドのセッション再アクティブ化が `AVAudioSessionErrorCodeCannotStartRecording`（561015905）で失敗する事例は Apple Developer Forums に多数あるが、その回答でも「背面で鳴らす・録るならセッションを mixable にせよ」と指摘されており、`mixWithOthers` がその条件にあたる。

`allowHapticsAndSystemSoundsDuringRecording: true` も併せて指定すると、**着信音が鳴っただけでは中断されず、実際に通話に出たときだけ中断**になる。中断の発生頻度そのものを下げられる。

```dart
// RecordConfig（stt_listening_pipeline.dart）
audioInterruption: AudioInterruptionMode.pauseResume,
iosConfig: IosRecordConfig(
  categoryOptions: [
    IosAudioCategoryOption.mixWithOthers,
    IosAudioCategoryOption.defaultToSpeaker,
    IosAudioCategoryOption.allowBluetooth,
    IosAudioCategoryOption.allowBluetoothA2DP,
  ],
  allowHapticsAndSystemSoundsDuringRecording: true,
),
```

---

## 実機検証（2026-08-01）

**条件**: iPhone 15 / iOS 26.5.2 / **release ビルド・デバッガ非接続**。

debug ビルドはデバッガの接続そのものが背面停止を抑止するため、判定に使えない。実際、debug では背面録音が動いたが、それが設定の効果なのかデバッガの効果なのかを区別できなかった。release で取り直して確定させている。

release では Dart のログが端末から届かなかったため、**判定はログではなく「背面で発話した内容がメモとして残るか」**で行った。アプリ自身を計測器として使う形になる。

**結果**

| 確認項目 | 結果 |
|---|---|
| 背面での録音・VAD・文字化の継続 | 動く |
| 中断（他アプリのマイク奪取）後の**背面のままの自動復帰** | 動く |
| 前面復帰後の録音 | 動く |
| `UIBackgroundModes` は `audio` だけで足りるか | 足りる（`fetch` なしで成立） |

**分かったこと**

- 録音と推論を別アイソレートへ引っ越す必要は**ない**。現行の `SttListeningPipeline` の構造のまま背面で動く
- 中断の再現には iOS 標準の「ボイスメモ」でのマイク奪取を使った。**実際の着信（CallKit）はより強い中断**なので、そちらでの再確認は残課題

**未検証**

- 実際の電話着信での中断・復帰
- 長時間（数時間規模）の連続動作とバッテリー消費
- アプリスワイプ終了からの挙動

---

## iOS 固有の注意

**常駐通知に相当する仕組みがない**

Android の常駐通知にあたるものが iOS にはない。録音中であることを画面外で示すには Live Activity かローカル通知の別実装になる。OS が出すステータスバーのオレンジインジケーターは自動で表示されるが、それだけに頼らない方が審査上は安全（→ `store_policy.md`）。

**審査のリスクが残る**

実装面の不確実性は検証で解消したが、`audio` バックグラウンドモードに対する審査は別問題として残る（→ `store_policy.md`）。
