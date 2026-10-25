# Step 4 【iOS】対応する OS の下限を、iOS 26 に上げる

## 目的

SpeechTranscriber が使える iOS 26 以上だけを対象にする。

iOS 26 未満の端末には、アプリを入れられなくなる。

文字化の動きは変えない（SenseVoice への戻り道は、まだ残っている）。


| 項目 | 今 | この step の後 |
| --- | --- | --- |
| 入れられる iOS | 13.0 以上（Widget は 16.1 以上） | 26.0 以上（Runner・Widget とも） |
| OS の版の確かめ | コードの中で「この版より新しいか」を確かめている | 26 以下の版の確かめは消す |


## やること

- `ios/Runner.xcodeproj/project.pbxproj` の `IPHONEOS_DEPLOYMENT_TARGET` を、すべて `26.0` にする
  - Runner とプロジェクト全体（Debug・Release・Profile）：今は `13.0`
  - Widget（`MomeoWidgets`。Debug・Release・Profile）：今は `16.1`
- Podfile の `platform :ios` を `26.0` で明記するかを確かめる（今はコメントのまま）。pod の下限が Runner と食い違うと、ビルドで警告が出る
- 26 以下の版の確かめを消す

| ファイル | 消す確かめ |
| --- | --- |
| `ios/Runner/SpeechTranscriberChannel.swift` | `guard #available(iOS 26.0, *)` 2つと、`SpeechTranscriberEngine` の `@available(iOS 26.0, *)` |
| `ios/Runner/AppDelegate.swift` | Live Activity の終了の `if #available(iOS 16.1, *)` と `@available(iOS 16.1, *)` |
| `ios/Runner/NativeMemoList.swift` | `@available(iOS 16.0, *)` 2つ |


## 確かめること

Swift を変えるので、`make run` し直す。

- 警告なくビルドできること
- 今と同じく、SpeechTranscriber で文字にできること
- Live Activity が、今と同じく録音中に出て、アプリスイッチャーから終了したときに消えること
- メモ一覧の文字選択のメニューが、今と同じであること（`NativeMemoList.swift` の確かめを消すため）
