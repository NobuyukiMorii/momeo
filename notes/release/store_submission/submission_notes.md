# ストア提出資料

両ストアの管理画面へ入力する内容をまとめた資料。文面はそのまま貼れる形にしてある（英文が正、日本語は対訳）。

momeo が録音するのは、アプリを開いている間だけ。バックグラウンドでは録音しないので、フォアグラウンドサービスの申告や、`audio` バックグラウンドモードの説明は要らない（理由と経緯は `notes/foreground_only_recording/impl/outline.md`）。

---

## Google Play — Data safety（データの安全性）

- 「アプリは必須のユーザーデータタイプを収集または共有しますか？」→ **いいえ**
- 根拠: Play の定義で「収集」は端末外への送信を指す。momeo はマイク音声・文字起こし・メモをすべて端末内で処理・保存し、送信しない。アカウント登録なし・解析 SDK なし・広告 SDK なし。

---

## App Store — 審査メモ（App Review Information → Notes）

```text
momeo is a voice-first memo app. Speech recognition runs entirely on device using Apple's SpeechTranscriber. Audio and transcripts never leave the device.

The app records only while it is open on screen. It does not declare any background modes; recording stops as soon as the app moves to the background, and starts again when the user returns. While recording, the app keeps the screen awake so that auto-lock does not cut off the user's speech.

How to verify:
1. Launch the app and grant microphone access.
2. Speak a short sentence: it appears as a text memo.
3. Go to the Home Screen and speak: nothing is recorded (no microphone indicator).
4. Return to the app: recording resumes, and the next sentence becomes a new memo.
```

（要旨: 認識はすべて Apple の SpeechTranscriber で端末内。録音はアプリを開いている間だけで、バックグラウンドモードは宣言していない。録音中は自動ロックで止まらないよう画面を点けたままにする。確認手順つき。）

---

## App Store — App Privacy（プライバシーラベル）

- 回答: **Data Not Collected**（データは収集していない）
- 根拠: Apple の定義でも「収集」は端末外への送信を指す。momeo からデバイス外に出るデータはない。

---

## 掲載文・ポリシーとの整合

| 項目 | 状態 |
|---|---|
| プライバシーポリシー（`docs/privacy.html` → momeo.jp/privacy.html） | 「録音するのは開いている間だけ」の文面に直してある。公開されるのは push して GitHub Pages に反映されたとき |
| ストア掲載文（説明文） | リポジトリには未作成。起票時は「アプリを開いている間だけ録音する」旨を本文に含め、実挙動と一致させる |
| ストアのスクリーンショット（`notes/release/screenshots/`） | 撮り直しが要る。今の画像には、画面上端の録音設定パネル（「このアプリを使ってる時だけ録音」の行）が写っている |
| Play のフィーチャーグラフィック | 未作成 |

---

## マニフェスト由来の権限

| 権限 | 由来 | 扱い |
|---|---|---|
| RECORD_AUDIO | momeo | マイク（実行時許可） |

画面を点けたままにするのは `wakelock_plus` で、画面のフラグ（`FLAG_KEEP_SCREEN_ON`）を使うため権限は要らない。提出前に、release ビルドのマージ後のマニフェストで、ほかの権限が入っていないかを確かめる。
