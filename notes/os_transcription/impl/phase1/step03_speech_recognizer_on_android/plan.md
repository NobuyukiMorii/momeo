# Step 3 【Android】SpeechRecognizer で文字にする

## 目的

Android の窓口 `OsTranscriberChannel` を作り、Android 13 以上の端末では、端末内の SpeechRecognizer（Google などが端末に入れている、OS の音声認識）で文字にする。

iOS はこの step では変わらない。


| 項目 | 今 | この step の後 |
| --- | --- | --- |
| Android 13 以上で、優先する言語のモデルが入っている端末 | SenseVoice で文字にする | SpeechRecognizer で文字にする。SenseVoice は読み込まない |
| Android 13 以上で、対応しているがモデルが入っていない端末 | SenseVoice で文字にする | ダウンロードを OS に頼み、その起動は SenseVoice で文字にする（入れば、次の起動から SpeechRecognizer） |
| Android 13 未満、または端末内の音声認識が無い端末 | SenseVoice で文字にする | 同じ |
| 文字にする言語 | 自動で判定する | SpeechRecognizer では、端末の「優先する言語」のうちモデルが入っている最初のものに決まる |


マイクは momeo の録音が持ったままにする。

SpeechRecognizer にはマイクを使わせず、VAD で区切った音をパイプ（`ParcelFileDescriptor.createPipe()`。書いた音をそのまま読み手へ流す管）で渡す。

自分の音を渡す仕組み（`EXTRA_AUDIO_SOURCE`）が Android 13 からなので、それ未満では使わない。

## やること

### `android/app/src/main/kotlin/jp/momeo/SpeechRecognizerChannel.kt`（新しく作る）

- チャンネル名は `jp.momeo/os_transcriber`、メソッドは `prepare` と `transcribe`（step 1 の表のとおり）
- SpeechRecognizer はメインスレッドでしか触れないので、ここの処理はすべてメインスレッドで行う
- `prepare`
  - Android 13 未満、または `SpeechRecognizer.isOnDeviceRecognitionAvailable` が false なら `unsupported`
  - `createOnDeviceSpeechRecognizer` で認識器を1つ作り、使い回す
  - `checkRecognitionSupport` で、端末に入っている言語（`installedOnDeviceLanguages`）と、入れられる言語（`supportedOnDeviceLanguages`・`pendingOnDeviceLanguages`）を聞く
  - `LocaleList.getDefault()` を上から見て、入っている言語があれば `ready`
  - 入っていないが入れられる言語があれば、`triggerModelDownload` で頼んで `downloading`（ダウンロード待ち・進行中の言語なら、頼み直さない）
  - どれも無ければ `unsupported`
  - 言語の一致は、言語と地域が同じものを優先し、無ければ言語だけ同じもの
- `transcribe`
  - Float32 の音を PCM16 にしてパイプへ書く（書き込みは別スレッド。読み手が追いつくまで待たされるため）
  - 認識の指定（`RecognizerIntent`）:

| 指定 | 値 | 理由 |
| --- | --- | --- |
| `EXTRA_AUDIO_SOURCE` と、その形式（PCM16・16kHz・1ch） | パイプの読み口 | マイクの代わりに渡した音を認識させる |
| `EXTRA_SEGMENTED_SESSION` | `EXTRA_AUDIO_SOURCE` | 流した音の終わりまで認識させ、結果を区間ごとに受け取る |
| `EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS` と `..._POSSIBLY_COMPLETE_...` | 5000 | これが無いと、Pixel 8a では区間ごとの結果が返らず、最初の区間しか文字にならなかった |
| `EXTRA_ENABLE_FORMATTING` | `FORMATTING_OPTIMIZE_QUALITY` | 句読点などを整えてもらう |
| `EXTRA_PREFER_OFFLINE` | true | 端末内で認識させる |


  - 区間ごとの結果（`onSegmentResults`）をつなげ、終わりの知らせ（`onEndOfSegmentedSession`）で返す。区切りなしで終わったとき（`onResults`）も返す
  - 聞き取れなかっただけのエラー（`ERROR_NO_MATCH`・`ERROR_SPEECH_TIMEOUT`）は、空の文字列として返す
  - 返事は1回だけにする。30秒たっても返事が無ければ、認識を取り消して失敗として返す（次の発話が詰まらないように）

### 登録

- `MainActivity.kt` で `SpeechRecognizerChannel` を作り、プロパティとして持ち続ける（`AudioSessionChannel` と同じ理由）

## 参照する spike のコード

`spike/android-speech-recognizer`。

spike との違い:

- チャンネル名は `jp.momeo/speech_transcriber` ではなく `jp.momeo/os_transcriber`
- 返事は `available` ではなく `state`（`ready`・`downloading`・`unsupported`）。spike はダウンロードを頼んだとき `available: false` を返している
- 調べるために入れたものは入れない: 途中経過の受け取り（`EXTRA_PARTIAL_RESULTS` と `onPartialResults` の中身）、結果の知らせの `Log.d`、`reply` の `Log.i`
- spike は入れられる言語に `pendingOnDeviceLanguages` を含めて毎回頼み直しているが、ダウンロード待ち・進行中の言語は頼み直さない

| ファイル | 場所 |
| --- | --- |
| `android/app/src/main/kotlin/jp/momeo/SpeechRecognizerChannel.kt` | ファイル全体（306行。上の違いを除く） |
| `android/app/src/main/kotlin/jp/momeo/MainActivity.kt` | 保持（16〜17行目）、作成（36〜39行目） |


## 確かめること

Kotlin を変えるので、`make run d=<Pixel>` し直す。

- 起動時のログに `[sttEngine] OS の文字起こしを使います（locale: ja-JP / ...）` が出ること
- 話した内容がメモとして一覧に出ること
- 10秒以上・途中に間のある発話が、最後まで文字になること（spike では、11.6秒の発話で文字が少なめだった）
- 話している間に「.」が出ること
