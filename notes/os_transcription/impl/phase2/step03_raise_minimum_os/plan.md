# Step 3 対応する OS の下限を、iOS 26・Android 13 に上げる

## 目的

OS の文字起こしが使える OS だけを対象にする。

iOS 26 未満・Android 13 未満の端末には、アプリを入れられなくなる。

文字化の動きは変えない（SenseVoice への戻り道は、まだ残っている）。


| 項目 | 今 | この step の後 |
| --- | --- | --- |
| 入れられる iOS | 13.0 以上（Widget は 16.1 以上） | 26.0 以上（Runner・Widget とも） |
| 入れられる Android | Flutter の既定の下限（`flutter.minSdkVersion`） | Android 13（API 33）以上 |
| OS の版の確かめ | コードの中で「この版より新しいか」を確かめている | 下限より古い版の確かめは消す |


## やること

### iOS

- `ios/Runner.xcodeproj/project.pbxproj` の `IPHONEOS_DEPLOYMENT_TARGET` を、すべて `26.0` にする
  - Runner とプロジェクト全体（Debug・Release・Profile）：今は `13.0`
  - Widget（`MomeoWidgets`。Debug・Release・Profile）：今は `16.1`
- Podfile の `platform :ios` を `26.0` で明記するかを確かめる（今はコメントのまま）。pod の下限が Runner と食い違うと、ビルドで警告が出る
- 下限より古い版の確かめを消す

| ファイル | 消す確かめ |
| --- | --- |
| `ios/Runner/SpeechTranscriberChannel.swift` | `guard #available(iOS 26.0, *)` 2つと、`SpeechTranscriberEngine` の `@available(iOS 26.0, *)` |
| `ios/Runner/AppDelegate.swift` | Live Activity の終了の `if #available(iOS 16.1, *)` と `@available(iOS 16.1, *)` |
| `ios/Runner/NativeMemoList.swift` | `@available(iOS 16.0, *)` 2つ |


### Android

- `android/app/build.gradle.kts` の `minSdk` を `33` にする（今は `flutter.minSdkVersion`）
- 下限より古い版の確かめを消す

| ファイル | 消す確かめ |
| --- | --- |
| `android/app/src/main/kotlin/jp/momeo/SpeechRecognizerChannel.kt` | `prepare` の「Android 13 未満のため使えません」 |
| `android/app/src/main/kotlin/jp/momeo/NativeMemoList.kt` | `Build.VERSION.SDK_INT >= Build.VERSION_CODES.R`（Android 11）の分岐。新しい版の側だけを残す |


**残すもの:** `NativeMemoList.kt` の `@TargetApi(34)`。Android 14 からの機能で、下限の 33 より新しいため。

## 確かめること

Swift と Kotlin を変えるので、iOS と Android の両方で `make run` し直す。

- iOS・Android とも、警告なくビルドできること
- Live Activity が、今と同じく録音中に出て、アプリスイッチャーから終了したときに消えること
- Android のメモ一覧で、画面下の余白（システムバーの高さ）が今と同じであること
