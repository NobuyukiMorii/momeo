# Step 1 【共通】区切った発話を、UI 側から OS の文字起こしに頼めるようにする

## 目的

OS の文字起こしを使うための、Dart 側の土台を作る。

ネイティブ側の窓口（iOS は step 2、Android は step 3）はまだ無いので、この step の後も両 OS とも SenseVoice で文字にする。

| 項目 | 今 | この step の後 |
| --- | --- | --- |
| 文字にするもの | SenseVoice | SenseVoice（今のまま） |
| エンジンの準備 | SenseVoice を読み込む | 先に OS の文字起こしが使えるかを窓口に問い合わせる。使えなければ（窓口が無いときも）SenseVoice を読み込む |
| 音声 isolate（UI とは別に、音の処理だけをする作業場所） | 区切った発話を、中の SenseVoice で文字にする | 切り替え `useOsTranscriber` が立っていれば、区切った発話を UI 側へ戻す。立っていなければ今のまま |


OS の文字起こしは、iOS と Android でネイティブの部品は違うが、Dart から見える窓口は1つにする（`OsTranscriberChannel`）。

## やること

### 窓口 `OsTranscriberChannel`（新しく作る）

`lib/platform/os_transcriber_channel.dart` を作る。

チャンネル名は `jp.momeo/os_transcriber`。

| メソッド | 渡すもの | 返ってくるもの |
| --- | --- | --- |
| `prepare` | なし | `state`（下の3つのどれか）と `detail`（言語や理由の説明） |
| `transcribe` | 1発話ぶんの音（16kHz・Float32List） | 文字列 |


| state | 意味 |
| --- | --- |
| `ready` | すぐ使える |
| `downloading` | 対応している言語だが、言語のモデルのダウンロードが終わっていない |
| `unsupported` | 端末か言語が対応していない |


返事を3つに分けるのは、Phase 2 で「ダウンロード中は待つ」「使えない端末ではそう出す」を出し分けるため。

Phase 1 では、`ready` 以外はすべて SenseVoice を使う。

### 音声 isolate（`stt_audio_worker.dart`）

- `spawn` に切り替え `useOsTranscriber`（既定は `false`）を足し、isolate へ渡す
- `useOsTranscriber` のときは、SenseVoice の認識器を作らない
- 区切った発話は、文字にする代わりに、専用のメッセージ `_SegmentCaptured` で UI 側へ戻す
- UI 側（`SttAudioWorker`）は `_SegmentCaptured` を受け取ったら、`OsTranscriberChannel.transcribe` に頼み、結果を `SttTranscribed` として流す
  - 発話の順を崩さないよう、頼むのは1つずつ（前の発話が終わってから次を頼む）
  - 失敗したら、結果待ち（「.」）が解けるよう、空の文字列として流す
- `stopListening` は、OS の文字起こしに頼んだ分が終わるまで待ってから返す
- `_AudioEngine` が UI 側へ送るものが `SttAudioEvent` と `_SegmentCaptured` の2種類になるので、送り先の型を `Object` にする（`onEvent` → `onMessage`）

### エンジンの準備（`stt_providers.dart`）

- 音声 isolate を立ち上げる前に、`OsTranscriberChannel.prepare()` を呼ぶ
  - iOS・Android のときだけ呼ぶ
  - `ready` なら `useOsTranscriber: true` で立ち上げる
  - それ以外と、呼び出しの失敗（窓口が無いときの `MissingPluginException` を含む）は `false`
- どちらを使うかを、`detail` と一緒に `debugPrint` で1行出す

※ SenseVoice のファイルの確かめと、Android のダウンロード待ちは、今のまま先に行う（OS の文字起こしを使うときも）。戻り先として要るため。

## 参照する spike のコード

`spike/android-speech-recognizer`（`spike/ios-speech-transcriber` の続き）。

spike では窓口の名前が `SpeechTranscriberChannel`、返事が `available`（true / false）だが、この step では最終形の名前と3つの state で作る。

spike の発話ごとの `debugPrint`（`_enqueueOsTranscription` の中）は入れない（`SttListeningPipeline` が debug のときに同じ内容を出している）。

| ファイル | 場所 |
| --- | --- |
| `lib/platform/speech_transcriber_channel.dart` | ファイル全体（これを `os_transcriber_channel.dart` として作り直す） |
| `lib/stt/stt_audio_worker.dart` | 冒頭のコメント（17〜19行目）、`spawn`（89〜100行目）、`_osTranscriptionQueue`（131行目）、`stopListening`（152〜157行目）、`_SegmentCaptured` の受け取り（223〜226行目）、`_enqueueOsTranscription`（232行目〜。248〜251行目の `debugPrint` は除く）、`_WorkerStartup`（295〜303行目）、`_SegmentCaptured`（338〜342行目）、isolate の起動（369〜375行目）、`_AudioEngine` の生成（419〜431行目）、`dispose`（522行目）、`_drainAndTranscribe`（565〜578行目）、`_transcribe`（586行目〜） |
| `lib/providers/stt_providers.dart` | import（2・9行目）、`_prepare` の呼び出し（86〜91行目）、`_canUseOsTranscriber`（104〜123行目） |


## 確かめること

- `flutter analyze` が通ること
- iOS・Android とも、起動時のログに `[sttEngine] OS の文字起こしを確かめられませんでした`（窓口がまだ無いため）が出て、今と同じく SenseVoice で文字にできること
