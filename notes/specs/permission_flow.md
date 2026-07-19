# 権限フロー仕様

momeoはライブ音声入力を前提とする音声ファーストのメモアプリであるため、マイク権限は必須です。

> 要求する権限は **iOS・Android ともマイク権限のみ**です。音声認識はオンデバイス STT（`sherpa_onnx` + VAD）で行うため、OS の音声認識（Speech Recognition）権限は使いません。

## プラットフォーム別の権限要件

| プラットフォーム | 必要な権限 | 表示される権限画面 |
| --- | --- | --- |
| iOS | マイク | マイク画面のみ |
| Android | マイク | マイク画面のみ |

## 権限画面の表示状態（UI State）

| 項目 (Field) | 取り得る値 (Values) | 意味 |
| --- | --- | --- |
| 権限の種類 (Type) | microphone | 対象となる権限 |
| 権限の状態 (State) | request / settings / unavailable | 画面の表示状態 |
| ステップ表示 | hidden | 必要権限が1つのみのため常に非表示 |

- **settings**: アプリ内の通常リクエストでは許可できず、OSの設定画面への誘導が必要な状態です。
  - 設定アプリへ誘導した後は、アプリ復帰時に権限状態を自動で再チェックします。許可されていれば操作なしで次へ進みます。
- **unavailable**: 端末や環境上、その機能が利用できない状態です。

## 権限フロー図

**iOS / Android 共通:**
```text
App Start
→ Splash
→ Check permissions
→ Microphone permission if needed
→ Preparation Gate（文字化エンジンの準備待ち。通常は素通り。notes/specs/preparation_gate.md）
→ Listening Screen
```

## ステップ表示ルール

必要な権限はマイクのみ（1ステップ）のため、**ステップ表示は常に非表示 (hidden)** です。

## 具体例

| プラットフォーム | マイク権限 | 画面遷移フロー |
| --- | --- | --- |
| iOS / Android | 未許可 | マイク → 準備ゲート → リスニング |
| iOS / Android | 許可済み | 準備ゲート → リスニング |

※ 準備ゲートは通常素通りするため、体感上は権限画面からそのままリスニングに進みます。

## 参照する既存デザインドキュメント

- notes/design/03_screen_states/details/PermissionMicrophoneRequest.md
- notes/design/03_screen_states/details/PermissionMicrophoneSettings.md
- notes/design/03_screen_states/details/PermissionMicrophoneUnavailable.md

## iOSで権限をoffにした時の挙動

iOSの設定アプリでマイク等のプライバシー権限をoffにすると、**iOSがアプリを即座に強制終了（SIGKILL）します。** これはiOSの意図的な仕様です（Apple DTS公式確認済み）。

- **本番では** アプリが終了してホーム画面に戻るだけです。ユーザーがアプリを再タップすると、通常通り起動し、権限フローが再実行されます（仕様通りの動作）。
- **開発中（flutter run）では** デバッガがアタッチされているため、プロセスが死んでもアプリがフリーズして見えます。これは開発時のみの現象で、バグではありません。

追加実装は不要です。

## 一次情報・参考リンク

- [Apple Developer Documentation: Protected Resources](https://developer.apple.com/documentation/bundleresources/protected-resources)
- [Android Developers: Request runtime permissions](https://developer.android.com/training/permissions/requesting)
