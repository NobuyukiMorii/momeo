# バックグラウンド録音 — iOS

概要と両OS共通の制約は `overview.md` を参照。

---

## 必要な対応

対応は2種類に分かれる。**動かすためのもの**は `record` だけで完結するが、**ストアに出すためのもの**は別に実装が要る。ここを混ぜると「iOS は設定だけで済む」と誤解しやすい。

### 動かすために必要なもの

1. `Info.plist` に `UIBackgroundModes` を追加する（Xcode の Capabilities で Background Modes → Audio を ON にすると同じ内容が書き込まれるので、実質1手順）
2. `AVAudioSession` のカテゴリを `record` または `playAndRecord` にして、セッションをアクティブに保つ
3. `RecordConfig` で中断時の挙動を指定する（既定のままだと中断後に復帰しない。後述。**本体に取り込み済み**）

### ストアに出すために必要なもの

4. **背面にいる間、録音中であることを示す表示**（後述。Live Activity かローカル通知の実装が要る）

Android は常駐通知が OS の要件として強制されるため、実装せずとも条件を満たす。**iOS にはその仕組みがなく、自分で作らない限り表示手段がない。** 4 は「あった方がよい改善」ではなく、iOS でバックグラウンド録音を出すなら付いてくる対応と考える。

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

## 設定を OFF にしたときの挙動はアプリが作る

`UIBackgroundModes` は Info.plist に書く静的な宣言で、**実行時に付け外しできない**。バックグラウンド録音を一度でも出すなら、設定が OFF のユーザーの端末でも `audio` は宣言された状態にある。

そのうえで録音中のセッションがアクティブなら、OS は設定の値と無関係にアプリを背面で生かし続ける。つまり **OFF は OS が実現してくれるものではなく、アプリが自分で書く挙動**になる。

| 設定 | 背面へ回ったとき | 前面へ戻ったとき |
|---|---|---|
| ON | 何もしない（OS が生かし続ける） | 何もしない |
| OFF | `SttListeningPipeline.stop()` を呼ぶ | `start()` を呼び直す |

`listening_providers.dart` はライフサイクルを見ておらず、パイプラインは一度起動したら止まらない。OFF 側を実装しない限り、**設定が OFF でも背面で録音が続く**。ユーザーからは見えず、審査でも見つかりにくい種類の不具合になる。

判定に使うのは `AppLifecycleState.paused` で、`inactive` は使わない。`inactive` はコントロールセンターを引き出しただけでも起きるため、そこで止めると前面にいるつもりのユーザーの録音が切れる。

Android には常駐サービスという明示的な停止対象があるので、この問題は iOS 固有になる。

---

## 中断からの復帰

`record` の `audioInterruption` の既定値は `AudioInterruptionMode.pause`（自動停止・**手動再開**）である。再開処理を書かない限り、着信や他アプリのマイク奪取で一度止まったらそのまま戻らない。

これは背面に限らず**前面でも同じ**で、対処しなければ通話後にリスニングが死んだままになる。バックグラウンド録音とは独立の不具合修正として、下記の設定を**本体に取り込み済み**（`stt_listening_pipeline.dart`）。

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

## 背面での「録音中」表示

Apple 2.5.14 は録音中であることの明確な視覚表示を求める（→ `store_policy.md`）。前面はアプリの画面で示せるが、**背面にいる間に何を見せるかが iOS では問題になる**。

OS が自動で出すのはステータスバーのオレンジインジケーターだけで、これは「いずれかのアプリがマイクを使っている」ことしか示さない。**momeo が録音しているとは分からない。**

Android の常駐通知に相当するものがないため、自分で作ることになる。選択肢は2つ。

| 方式 | 見え方 | 実装量 | 審査リスク |
|---|---|---|---|
| 何もしない | オレンジインジケーターのみ | ゼロ | 残る。2.5.14 を満たすかは審査員の判断次第 |
| **ローカル通知** | 背面遷移時に通知を出す。出しっぱなしにはできず、ユーザーが消せる | 小（Flutter のパッケージで完結） | かなり下がる |
| Live Activity | ロック画面と Dynamic Island に**出続ける**。Android の常駐通知に最も近い | 大（Swift の Widget Extension が別途必要。Dart だけでは書けない） | 最も低い |

**初期リリースはローカル通知で足りると考える。** 背面へ入った時点で1回通知を出すだけでも、「アプリを閉じたが録音は続いている」ことは伝わり、何もしない場合とは大きく違う。Live Activity はリリース後の反応を見てから判断すればよい。

---

## 審査のリスク

実装面の不確実性は実機検証で解消したが、`audio` バックグラウンドモードに対する審査は別問題として残る。**iOS 側で残る唯一のリスクがここ**（→ `store_policy.md`）。
