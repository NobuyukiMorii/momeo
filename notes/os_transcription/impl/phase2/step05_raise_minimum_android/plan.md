# Step 5 【Android】対応する OS の下限を、Android 13 に上げる

## 目的

自分の音を SpeechRecognizer に渡せる Android 13（API 33）以上だけを対象にする。

Android 13 未満の端末には、アプリを入れられなくなる。

文字化の動きは変えない（SenseVoice への戻り道は、まだ残っている）。


| 項目 | 今 | この step の後 |
| --- | --- | --- |
| 入れられる Android | Flutter の既定の下限（`flutter.minSdkVersion`） | Android 13（API 33）以上 |
| OS の版の確かめ | コードの中で「この版より新しいか」を確かめている | 33 以下の版の確かめは消す |


## やること

- `android/app/build.gradle.kts` の `minSdk` を `33` にする（今は `flutter.minSdkVersion`）
- 33 以下の版の確かめを消す

| ファイル | 消す確かめ |
| --- | --- |
| `android/app/src/main/kotlin/jp/momeo/SpeechRecognizerChannel.kt` | `prepare` の「Android 13 未満なら `unsupported`」 |
| `android/app/src/main/kotlin/jp/momeo/NativeMemoList.kt` | `Build.VERSION.SDK_INT >= Build.VERSION_CODES.R`（Android 11）の分岐。新しい版の側だけを残す |


**残すもの:** `NativeMemoList.kt` の `@TargetApi(34)`。Android 14 からの機能で、下限の 33 より新しいため。

## 確かめること

Kotlin と Gradle の設定を変えるので、`make run` し直す。

- 警告なくビルドできること
- 今と同じく、SpeechRecognizer で文字にできること
- メモ一覧で、画面下の余白（システムバーの高さ）が今と同じであること（`NativeMemoList.kt` の分岐を消すため）
