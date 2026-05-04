# リスニングフロー仕様

## 概要
権限許可後、アプリは自動的にリスニング状態で開始されます。ユーザーは録音ボタンを探すことなく話し始めることができます。

## 画面構成

1. **現在リスニング中のカード (アクティブ)**
   - 波形等のインジケーターを表示し、認識テキストを随時更新します。日時は非表示です。
2. **確定済みメモカード**
   - 波形を非表示にし、右下に作成日時を表示します。長押しでテキストコピーが可能です。

## メモ確定条件
発話が1つの「確定済みメモカード」として保存されるトリガーは以下の2つのいずれかです。

1. **OS が認識完了を通知した時**
2. **無音（テキスト更新の停止）が `1.5秒` 続いた時**

どちらかの条件を満たした時点で現在のカードを確定し、次の発話に備えて新しいリスニング中カードを作成します。

## プラットフォーム別の OS Signals（認識完了の通知）
OSが「認識完了」を通知するシグナルはプラットフォームによって異なります。

| プラットフォーム | 完了シグナル (OS Events) | 説明 |
| --- | --- | --- |
| iOS | `isFinal = true` | API が「この発話セグメントの認識結果はこれが最終である」と明確に返してきた状態。 |
| Android | `onEndOfSpeech` / `onResults` | API が「ユーザーが話し終わった」と検知した、または「最終的な認識結果である」と返ってきた状態。 |

## 確定フロー

```text
ユーザーが話す
↓
アクティブカードのテキストが更新される
↓
【 確定条件 】
 ├─ OS から完了シグナル (isFinal / onResults等) が届く
 └─ または、1.5秒間テキストの更新がない
↓
現在のカードを「確定済みメモカード」にする
↓
新しい「現在リスニング中のカード」を作成して待機
```

## 今後の検証項目
「無音検知 1.5秒」という基準値が実際の利用感として心地よいかどうかは、実機検証を通じて調整します。

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
