# Step 2 【iOS】SpeechTranscriber で文字にする

## 目的

iOS の窓口 `OsTranscriberChannel` を作り、iOS 26 以上の端末では SpeechTranscriber（iOS 26 から使える、OS 内蔵の端末内の文字起こし）で文字にする。

Android はこの step では変わらない（SenseVoice のまま）。


| 項目 | 今 | この step の後 |
| --- | --- | --- |
| iOS 26 以上で、使える言語がある端末 | SenseVoice で文字にする | SpeechTranscriber で文字にする。SenseVoice は読み込まない |
| iOS 26 未満、または使える言語が無い端末 | SenseVoice で文字にする | 同じ |
| 文字にする言語 | 自動で判定する | SpeechTranscriber では、端末の「優先する言語」のうち使える最初のものに決まる |
| 言語のモデルが端末に無いとき | — | prepare の中で、OS にダウンロードさせて入るまで待つ（その間、準備ゲート画面はアプリ名のまま） |


言語のモデルのダウンロードを待たずに「ダウンロード中」と返し、画面に出すのは step 7。

## やること

### `ios/Runner/SpeechTranscriberChannel.swift`（新しく作る）

窓口と、SpeechAnalyzer（SpeechTranscriber を動かす OS の部品）で1発話ずつ文字にする係 `SpeechTranscriberEngine` を置く。

- チャンネル名は `jp.momeo/os_transcriber`、メソッドは `prepare` と `transcribe`（step 1 の表のとおり）
- `prepare`
  - iOS 26 未満なら `unsupported`
  - `SpeechTranscriber.isAvailable` が false なら `unsupported`
  - `Locale.preferredLanguages` を上から見て、`SpeechTranscriber.supportedLocale(equivalentTo:)` が返す最初の言語を使う。どれも無ければ `unsupported`
  - その言語のモデルが無ければ、`AssetInventory.assetInstallationRequest` でダウンロードさせ、入るまで待ってから `ready`
  - `SpeechAnalyzer.bestAvailableAudioFormat` で、受け付ける音の形式を覚えておく
- `transcribe`
  - 届いた音（16kHz・Float32）を `AVAudioPCMBuffer` にし、受け付ける形式と違えば `AVAudioConverter` で変える
  - 発話ごとに `SpeechAnalyzer` を作り、音を1回だけ流して入力を閉じ、`finalizeAndFinish` で確定させる
  - 結果（`transcriber.results`）の文字をつなげて返す
- `FlutterResult` はメインスレッドで呼ぶ（`MainActor.run`）
- 最低対応の版はまだ iOS 13 なので、`#available(iOS 26.0, *)` で守る（外すのは step 4）

### 登録

- `ios/Runner/AppDelegate.swift`：`SttModelChannel` の登録の後に、`SpeechTranscriberChannel` を登録する
- `ios/Runner.xcodeproj/project.pbxproj`：`SpeechTranscriberChannel.swift` をファイル参照・Runner グループ・Compile Sources に足す（Xcode で足すか、4行を手で足す）

## 参照する spike のコード

`spike/ios-speech-transcriber` の最終形（`spike/android-speech-recognizer` にも同じものが入っている）。

spike との違い:

- チャンネル名は `jp.momeo/speech_transcriber` ではなく `jp.momeo/os_transcriber`
- 返事は `available` ではなく `state`（`ready`・`unsupported`）
- `handlePrepare` の `NSLog` は入れない（同じ内容を Dart が出す）

| ファイル | 場所 |
| --- | --- |
| `ios/Runner/SpeechTranscriberChannel.swift` | ファイル全体（234行） |
| `ios/Runner/AppDelegate.swift` | 登録（28〜31行目） |
| `ios/Runner.xcodeproj/project.pbxproj` | `SpeechTranscriberChannel.swift` の4行（`5A7C0E1D2B3F4A5600C1D001`・`...D002`） |


## 確かめること

Swift を変えるので、`make run d=<iPhone> mode=profile` し直す（debug は、iOS 26 だとデバッガがつながらず画面が真っ白のまま止まることがある）。

- 起動時のログに `[sttEngine] OS の文字起こしを使います（locale: ja_JP / format: ...）` が出ること
- 話した内容がメモとして一覧に出て、句読点が付くこと
- 10秒以上の発話も、最後まで文字になること
