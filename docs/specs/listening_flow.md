# リスニングフロー仕様

## 概要
権限許可後、アプリは自動的にリスニング状態で開始されます。ユーザーは録音ボタンを探すことなく話し始めることができます。

## 画面構成

1. **現在リスニング中のカード (アクティブ)**
   - 波形等のインジケーターを表示し、認識テキストを随時更新します。日時は非表示です。
2. **確定済みメモカード**
   - 波形を非表示にし、右下に作成日時を表示します。長押しでテキストコピーが可能です。

## メモ確定条件
`speech_to_text` パッケージの `pauseFor` オプションを `1.5秒` に設定する。
無音が 1.5秒 続いた時点でパッケージが自動的に認識を終了し、`onStatus = 'done'` を通知する。
アプリはこの通知を確定トリガーとして扱う。

## 確定フロー

```text
ユーザーが話す
↓
アクティブカードのテキストが更新される
↓
【 確定条件 】
 └─ 無音が 1.5秒 続き、パッケージが onStatus = 'done' を通知する
↓
現在のカードを「確定済みメモカード」にする
↓
新しい「現在リスニング中のカード」を作成して listen() を再開
```

## listen() のオプション方針

- **部分結果を有効にする**: アクティブカードのテキストをリアルタイムで更新するために、部分結果を受け取る設定にする
- **無音タイムアウトを設定する**: `pauseFor` で無音検知の時間を設定する。基準は 1.5秒だが、実機検証で調整する
- **最大リスニング時間を設定する**: `listenFor` で1セッションの上限時間を設ける
- **ロケールを明示する**: `localeId` には `systemLocale()` の値を使い、ユーザーの第一言語で認識する

## 今後の検証項目
`pauseFor` の値が実際の利用感として心地よいかどうかは、実機検証を通じて調整します。

## 参照する既存デザインドキュメント

- docs/design/03_screen_states/details/ListeningInitial.md
- docs/design/03_screen_states/details/ListeningFirstItem.md
- docs/design/03_screen_states/details/ListeningSecondItem.md
- docs/design/03_screen_states/details/ListeningThirdItem.md
- docs/design/03_screen_states/details/ListeningManyItemsOverview.md

## 一次情報・参考リンク

- [Apple Developer Documentation: SFSpeechRecognitionResult.isFinal](https://developer.apple.com/documentation/speech/sfspeechrecognitionresult/isfinal)
- [Apple Developer Documentation: SFSpeechRecognitionTaskDelegate](https://developer.apple.com/documentation/speech/sfspeechrecognitiontaskdelegate)
- [Android Developers: RecognitionListener](https://developer.android.com/reference/android/speech/RecognitionListener)
- [Android Developers: RecognizerIntent](https://developer.android.com/reference/android/speech/RecognizerIntent)
