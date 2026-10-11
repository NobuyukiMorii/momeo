# Step 2 リスニングを止めるときに、イヤホンを手放す（iOS）

## 目的

リスニングを止めたあと、Bluetooth イヤホンが通話用の方式（HFP）のまま残らないようにする。

録音ライブラリ（record）は、録音を閉じてもオーディオセッションを有効なままにする。そのため、止めたあとも momeo がイヤホンをつかみ続け、他のアプリの音がこもる。「このアプリを使ってる時だけ録音」では背面に回るたびに止めるので、特に目立つ。


| 項目 | 今 | この step の後 |
| --- | --- | --- |
| リスニングを止めたあとのイヤホン | 通話用（HFP）のまま | 音楽用の方式（A2DP）に戻る |
| 「このアプリを使ってる時だけ録音」で背面に回したあと、他のアプリの音 | こもる | こもらない |
| Android | — | 変わらない |


録音している最中のこもり（Bluetooth のマイクを使っている間）は、この step では直らない（step 5 で直す）。

## やること

- iOS 側に窓口 `AudioSessionChannel`（Swift）を足し、`releaseAudioSession` だけを持たせる（`setActive(false, options: .notifyOthersOnDeactivation)`）
- `AppDelegate` で窓口を登録し、Xcode プロジェクトにファイルを登録する
- Dart 側に窓口 `AudioSessionChannel` を足す（`lib/platform/audio_session_channel.dart`）
- `stop()` で録音を閉じたあと、iOS だけセッションを手放す（失敗してもログだけ残して止めきる）

窓口の名前は、このあとの step で問い合わせを足していく前提で、最初から `AudioSessionChannel` にする。

## 参照する `spike/yield-to-other-audio` のコード

spike の窓口には、このあとの step の問い合わせも入っているので、`releaseAudioSession` に関わる部分だけを見る。


| ファイル | 場所 |
| --- | --- |
| `ios/Runner/AudioSessionChannel.swift` | 冒頭のコメントと `channelName`（1〜9行目）、`releaseAudioSessionMethod`（13行目）、`register`（19行目〜）、`handleReleaseAudioSession`（62行目〜） |
| `ios/Runner/AppDelegate.swift` | 登録（28〜31行目） |
| `ios/Runner.xcodeproj/project.pbxproj` | `AudioSessionChannel.swift` の4か所（28・87・241・524行目） |
| `lib/platform/audio_session_channel.dart` | `_channel`（12行目）、`releaseAudioSession`（37行目〜） |
| `lib/stt/stt_listening_pipeline.dart` | `stop()` の呼び出し（247〜248行目）、`_releaseAudioSessionOnIos`（528行目〜） |


Xcode プロジェクトへの登録は `xcodeproj`（Ruby）で行うと、無関係な行（`NativeMemoList.swift`）の並びまで変わる。差分を最小にするため、その行は元の位置に戻す。
