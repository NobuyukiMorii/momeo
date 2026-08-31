# バックグラウンド録音のストア提出資料

バックグラウンド録音を含むアプリとして提出するときに、両ストアの管理画面へ入力する内容をまとめた資料。文面はそのまま貼れる形にしてある（英文が正、日本語は対訳）。

計画上の位置づけは `notes/background_recording/impl/phase3/step08_store_submission_materials.md`。

---

## Google Play — フォアグラウンドサービス申告

場所: Play Console → App content（アプリのコンテンツ）→ Foreground service permissions。

マージ後のマニフェストには FGS タイプが**2つ**入っているため、申告も2つ必要になる。

| タイプ | 由来 |
|---|---|
| microphone | momeo 本体（flutter_foreground_task 経由） |
| dataSync | Play Asset Delivery（モデル配布用の Google のライブラリが持ち込む `ExtractionForegroundService`） |

### microphone の申告

- ユースケース: 音声録音（voice recording）系の定義済み項目を選ぶ
- 機能の説明:

```text
momeo is a voice memo app that turns spoken thoughts into text notes using fully on-device speech recognition. When the user explicitly enables "keep recording while using other apps" (off by default, guarded by a consent dialog), the app runs a microphone foreground service so it can keep capturing and transcribing the user's voice while they use other apps or the screen is off. A persistent notification with a stop button is shown the whole time, and audio never leaves the device.
```

（対訳: momeo は、話した思考をオンデバイス音声認識でテキストメモにする音声メモアプリ。ユーザーが「ほかのアプリを使っていても録音」を明示的に有効にしたとき（初期値は無効・同意ダイアログあり）だけ microphone タイプのフォアグラウンドサービスを動かし、他アプリの使用中や画面消灯中も録音と文字化を続ける。実行中は停止ボタン付きの常駐通知を出し続け、音声は端末の外に出ない。）

- 中断された場合のユーザーへの影響:

```text
If the system defers or interrupts the service, speech spoken during that time is not captured, so those voice memos are permanently lost. Uninterrupted capture is the core value of the feature the user opted into.
```

（対訳: サービスが中断されると、その間の発話は取り込まれず、メモとして永久に失われる。途切れない取り込みがこの機能の価値そのもの。）

- 実演動画: リンクを必ず添える（YouTube 限定公開で可）。**ユーザーが機能をトリガーする手順**が映っている必要があるので、次のシーン構成で撮る。

```text
1. リスニング画面 → 下端の帯をタップして選択肢を出す
2. 「ほかのアプリを使っていても録音」をタップ → 開示ダイアログ → 有効にする
3. ホームへ戻る → 通知シェードを開き、常駐通知（停止ボタン付き）を見せる
4. 他のアプリの画面のまま、短い一文を話す
5. momeo に戻る → 話した内容がメモとして増えている
```

- 動画リンク（アップ後にここへ記録する）: ＿＿＿＿＿＿＿＿

### dataSync の申告

- 機能の説明:

```text
This foreground service comes from the Google Play Asset Delivery library (com.google.android.play.core.assetpacks.ExtractionForegroundService). The app delivers its on-device speech-recognition model (~625 MB) as a fast-follow asset pack, and the library uses this service to extract the pack after download. The app's own code never starts a dataSync foreground service.
```

（対訳: このサービスは Play Asset Delivery のライブラリが持ち込むもの。momeo はオンデバイス音声認識モデル（約625MB）を fast-follow のアセットパックで配布しており、ダウンロード後の展開にライブラリがこのサービスを使う。アプリ自身のコードが dataSync のサービスを起動することはない。）

- 中断された場合のユーザーへの影響:

```text
If extraction is interrupted, the speech-recognition model is not ready, and the app cannot transcribe until extraction completes on a later launch.
```

- 実演動画: 初回起動で準備ゲート（モデルの準備画面）が進む様子を撮る。

---

## Google Play — Data safety（データの安全性）

- 「アプリは必須のユーザーデータタイプを収集または共有しますか？」→ **いいえ**
- 根拠: Play の定義で「収集」は端末外への送信を指す。momeo はマイク音声・文字起こし・メモをすべて端末内で処理・保存し、送信しない。アカウント登録なし・解析 SDK なし・広告 SDK なし。`INTERNET` 権限の用途は Google Play からのモデル取得（Play Asset Delivery）のみで、ユーザーデータの送信はない。

---

## App Store — 審査メモ（App Review Information → Notes）

`audio` バックグラウンドモードを「再生用」とみなされてリジェクトされた事例への先回りとして、提出のたびに次を貼る。

```text
momeo is a voice-first memo app. All speech recognition runs entirely on device (sherpa-onnx with a bundled model). Audio and transcripts never leave the device, and the app makes no network requests for recognition.

About UIBackgroundModes "audio": the app uses it only to continue RECORDING (not playback) when the user explicitly turns on "keep recording while using other apps". This option is OFF by default, requires an explicit consent dialog, and can be turned off at any time from the same screen. While recording in the background, iOS shows the orange microphone indicator, and the app additionally shows a Live Activity on the Lock Screen with the app name and the number of memos captured.

How to verify:
1. Launch the app and grant microphone access.
2. Tap the status band at the bottom of the listening screen, then choose the right-hand card ("ほかのアプリを使っていても録音") and confirm the consent dialog.
3. Lock the screen and speak a short sentence.
4. Wake the screen: a Live Activity "momeo — 音声を認識しています" is visible on the Lock Screen.
5. Unlock and return to the app: the sentence appears as a new text memo.
6. Switch back to the left-hand card: backgrounding the app now stops recording (the default behavior).
```

（要旨: すべてオンデバイス・外部送信なし。audio は再生ではなく録音の継続のためで、デフォルト OFF・同意ダイアログ・いつでも解除可。録音中はオレンジの点に加えて Live Activity を表示。確認手順つき。）

---

## App Store — App Privacy（プライバシーラベル）

- 回答: **Data Not Collected**（データは収集していない）
- 根拠: Apple の定義でも「収集」は端末外への送信を指す。momeo からデバイス外に出るデータはない。

---

## 掲載文・ポリシーとの整合

| 項目 | 状態 |
|---|---|
| プライバシーポリシー（momeo.jp/privacy.html） | 更新済み（バックグラウンド録音・端末内保存のみ・外部送信なし → `notes/background_recording/impl/phase3/step07_update_wording_and_docs.md`） |
| ストア掲載文（説明文） | リポジトリには未作成。起票時は本資料の機能説明をベースにし、「設定で有効にしたときだけバックグラウンドでも録音する」旨を本文に含めて実挙動と一致させる |
| ストアのスクリーンショット（`notes/release/screenshots/`） | 現行 UI（検索フィールド・ボトムシート）入りで撮り直し済み（撮影はスクリプト。`scripts/take_ios_screenshots.sh` / `take_android_screenshots.sh`） |
| Play のフィーチャーグラフィック | 未作成（バックグラウンド録音とは別件の宿題） |

---

## マニフェスト由来の権限と申告への影響

マージ後のマニフェスト（debug ビルドで確認）に入る権限の由来一覧。審査や申告で聞かれたときの答え。

| 権限 / 要素 | 由来 | 扱い |
|---|---|---|
| RECORD_AUDIO | momeo | マイク（実行時許可） |
| FOREGROUND_SERVICE / FOREGROUND_SERVICE_MICROPHONE | momeo（flutter_foreground_task） | microphone の申告で説明 |
| FOREGROUND_SERVICE_DATA_SYNC / dataSync のサービス | Play Asset Delivery | dataSync の申告で説明 |
| POST_NOTIFICATIONS | momeo（常駐通知）と Play Asset Delivery | — |
| RECEIVE_BOOT_COMPLETED | flutter_foreground_task の BootReceiver と Play Asset Delivery | **削らない**。Play Asset Delivery が再起動後のアセット展開の再開に使うため、削ると配布が壊れる恐れがある。flutter_foreground_task の「再起動でサービスを立て直す」機能は momeo では使っていない |
| WAKE_LOCK | flutter_foreground_task と Play Asset Delivery | — |
| INTERNET / ACCESS_NETWORK_STATE | Flutter / Play Asset Delivery | モデル取得のみ。ユーザーデータの送信なし |

## 参考リンク

- [フォアグラウンドサービスと全画面インテントの要件（Play Console ヘルプ）](https://support.google.com/googleplay/android-developer/answer/13392821)
- [Foreground service types are required（Android Developers）](https://developer.android.com/about/versions/14/changes/fgs-types-required)
- 規約調査の本体: `notes/background_recording/store_policy.md`
