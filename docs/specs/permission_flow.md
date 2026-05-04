# 権限フロー仕様

momeoはライブ音声入力を前提とする音声ファーストのメモアプリであるため、マイク権限は必須です。

## プラットフォーム別の権限要件

| プラットフォーム | 必要な権限 | 表示される権限画面 |
| --- | --- | --- |
| iOS | マイク、音声認識 | マイク画面、音声認識画面 |
| Android | マイク | マイク画面のみ |

## 権限画面の表示状態（UI State）

| 項目 (Field) | 取り得る値 (Values) | 意味 |
| --- | --- | --- |
| 権限の種類 (Type) | microphone / speechRecognition | 対象となる権限 |
| 権限の状態 (State) | request / settings / unavailable | 画面の表示状態 |
| ステップ表示 | hidden / 1/2 / 2/2 | 複数ステップ時のみ表示 |

- **settings**: アプリ内の通常リクエストでは許可できず、OSの設定画面への誘導が必要な状態です。
- **unavailable**: 端末や環境上、その機能が利用できない状態です。

## 権限フロー図

**iOS:**
```text
App Start
→ Onboarding if needed
→ Check permissions
→ Microphone permission if needed
→ Speech Recognition permission if needed
→ Listening Screen
```

**Android:**
```text
App Start
→ Onboarding if needed
→ Check permissions
→ Microphone permission if needed
→ Listening Screen
```

## ステップ表示ルール

ステップ表示は、今回の起動時にユーザーが通過する必要のある権限ステップ数に基づいて決めます。

| 状況 (Case) | 表示画面 | ステップ表示 |
| --- | --- | --- |
| iOS: マイクと音声認識の両方が必要 | マイク | 1/2 |
| iOS: マイクと音声認識の両方が必要 | 音声認識 | 2/2 |
| iOS: マイクのみ必要 | マイク | 非表示 (hidden) |
| iOS: 音声認識のみ必要 | 音声認識 | 非表示 (hidden) |
| Android: マイクが必要 | マイク | 非表示 (hidden) |
| 全OS: 端末で利用不可 | 利用不可 (unavailable) 画面 | 非表示 (hidden) |

## 具体例

| プラットフォーム | マイク権限 | 音声認識権限 | 画面遷移フロー |
| --- | --- | --- | --- |
| iOS | 未許可 | 未許可 | マイク 1/2 → 音声認識 2/2 → リスニング |
| iOS | 許可済み | 未許可 | 音声認識 → リスニング |
| iOS | 未許可 | 許可済み | マイク → リスニング |
| Android | 未許可 | (不要) | マイク → リスニング |
| Android | 許可済み | (不要) | リスニング |

## 参照する既存デザインドキュメント

- docs/design/03_screen_states/details/PermissionMicrophoneRequest.md
- docs/design/03_screen_states/details/PermissionMicrophoneSettings.md
- docs/design/03_screen_states/details/PermissionMicrophoneUnavailable.md
- docs/design/03_screen_states/details/PermissionSpeechRecognitionRequest.md
- docs/design/03_screen_states/details/PermissionSpeechRecognitionSettings.md
- docs/design/03_screen_states/details/PermissionSpeechRecognitionUnavailable.md

## 一次情報・参考リンク

- [Apple Developer Documentation: Asking Permission to Use Speech Recognition](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition)
- [Apple Developer Documentation: Protected Resources](https://developer.apple.com/documentation/bundleresources/protected-resources)
- [Android Developers: Automatic Speech Recognition / SpeechRecognizer and RECORD_AUDIO](https://developer.android.com/develop/xr/jetpack-xr-sdk/asr)
- [Android Developers: Request runtime permissions](https://developer.android.com/training/permissions/requesting)
