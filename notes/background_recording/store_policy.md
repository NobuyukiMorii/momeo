# バックグラウンド録音 — ストア規約と提出物

概要は `overview.md`、実装は `ios.md` / `android.md` を参照。

「外部に送信しない」ことは規約上かなり有利に働くが、**録音していること自体の開示義務は免除されない**。ここが最大の勘所である。

---

## 1. Apple（App Store Review Guidelines）

| ガイドライン | 内容 | momeo への影響 |
|---|---|---|
| 2.5.4 | "Multitasking apps may only use background services for their intended purposes: VoIP, audio playback, location, task completion, local notifications, etc." | 条文に「録音」の明示はない。列挙されているのは `audio playback`（再生）であり、**この条項を根拠に `audio` モードのリジェクトが実際に起きている** |
| 2.5.14 | "Apps must request explicit user consent and provide a clear visual and/or audible indication when recording, logging, or otherwise making a record of user activity. This includes any use of the device camera, microphone, screen recordings, or other user inputs." | **最も効く条項**。録音中であることの明示的な視覚表示が必須 |
| 5.1.1(ii) | 収集への同意取得。purpose string で用途を完全に説明すること。同意を撤回する分かりやすい手段の提供も求められる | `NSMicrophoneUsageDescription` に「バックグラウンドでも録音する」旨を追記する必要がある。**OFF にできない実装はこの条項に抵触する** |
| 5.1.2(i) | 第三者への提供には明示的な許可が必要 | オンデバイス完結のため該当しない（＝有利） |

iOS 14 以降はマイク使用中にステータスバーへオレンジのインジケーターが自動表示される。2.5.14 の「視覚的な表示」の一部は OS が担保してくれるが、アプリ側でも「バックグラウンドで聞いている」と分かる表示を出す方が安全。

### `audio` バックグラウンドモードのリジェクトリスク

Apple のレビューは `audio` モードに対して「バックグラウンドで音を鳴らすこと（"provide audible content to the user while in the background"）」を求める文言でリジェクトを出しており、この定型文言を受け取った事例が Apple Developer Forums に複数ある。一方、Apple 自身のドキュメントは `audio` モードの用途に録音も含めて記述しており、記載と審査運用が食い違っていることが開発者から指摘されている。

ボイスレコーダー系アプリが実際に配信されている以上「不可」ではないが、**「Info.plist を足すだけ」で審査を通る前提は置けない**。実装面の不確実性は実機検証で解消したため、**残る iOS 側のリスクはここだけ**である。

---

## 2. Google Play

提出時の事務手続きが増える点に注意。

### (1) フォアグラウンドサービス タイプの宣言（Play Console の App Content）

- Android 14+ をターゲットにするアプリは必須。momeo の `android/app/build.gradle.kts` は `flutter.targetSdkVersion` をそのまま参照しており、現在の Flutter のデフォルトは 34 以上なので確実に該当する
- 提出時に「機能の説明」「中断された場合にユーザーが受ける影響」に加えて、**その機能を実演した動画へのリンク**が必要
- `TYPE_MICROPHONE` の想定用途として "Capture audio input, for example, voice commands for virtual assistant without saving, voice recording." が挙げられており、momeo は素直に当てはまる
- 原則は "the user should be aware that a foreground service task is running on their device"

### (2) Prominent disclosure（目立つ開示）と同意 — User Data ポリシー

- バックグラウンド収集は明確に対象。"for example, if data collection occurs in the background when the user is not engaging with your app"
- 開示は**アプリの通常利用の流れの中で表示**すること（設定メニューの奥はNG）
- 開示はマイク権限のリクエストより**前**に出すこと
- 同意は**能動的な操作**（タップ・チェック）で取ること。画面遷移を同意とみなすのはNG

### (3) Data safety フォーム

- 端末内処理のみ・外部送信なしを申告できるため、ここは強みになる

---

## 3. 実装要件

規約上はグレーではなく、要件を満たせば白。以下は規約由来のものと、審査・評価の観点から入れておきたいものの一覧。

### 規約上ほぼ必須

1. **設定での ON / OFF**（初期値は OFF）。Play は能動的な操作による同意を求め、Apple は同意を撤回する手段を求めるため、両方の受け皿になる
2. **ON にするタイミングで専用の開示＋同意画面**を出す（Play の prominent disclosure 要件をここで満たす）。マイク権限のリクエストより前に表示する
3. **バックグラウンド中は「録音中」を明示する**。Android は常駐通知が OS の要件として強制されるため実装不要。**iOS は相当する仕組みがなく、ローカル通知か Live Activity を自分で作る必要がある**（→ `ios.md`。iOS 側で唯一、設定では済まない実装項目）
4. **`NSMicrophoneUsageDescription` の更新**（バックグラウンドでも録音する旨）
5. **プライバシーポリシーの更新**（バックグラウンド録音・端末内保存のみ・外部送信なし）

### 入れておきたいもの

6. **常駐通知に停止ボタン**（Android）。通知を消してもサービスは止まらないため、実際に止める手段が要る
7. **時間上限やバッテリー閾値での自動停止**（審査でもユーザー評価でもプラスに働く）
8. **マイク権限が取り消されたときの処理**。バックグラウンドだと「動いているのに録れていない」状態に気づけない
9. **`record` の `audioInterruption` を `pauseResume` に**（→ `ios.md`。既定のままだと中断後に復帰しない）
10. **常駐通知の重要度を上げる**（→ `android.md`。既定では「サイレント」欄に入る）

---

## 4. 提出時に用意するもの

| 提出先 | 用意するもの |
|---|---|
| Google Play Console | フォアグラウンドサービスの**実演動画へのリンク**、機能の説明、中断時の影響 |
| Google Play Console | Data safety フォームの更新 |
| App Store Connect | 審査メモ（機能の目的、**端末内処理で外部送信がないこと**、確認手順） |
| App Store Connect | App Privacy（プライバシーラベル）の更新 |
| 両方 | プライバシーポリシー、ストア掲載文（実際の挙動と食い違わせない） |

実演動画は忘れられやすい。Play の FGS 宣言では必須項目である。
