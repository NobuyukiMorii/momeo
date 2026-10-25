# Step 4 SenseVoice への戻り道を外し、使えない端末では準備ゲート画面にそう出す

## 目的

文字化を、OS の文字起こしだけにする。

OS の文字起こしが使えない端末では、SenseVoice で文字にする代わりに、準備ゲート画面（リスニングの前に、文字化の準備が終わるまで待つ画面）に「この端末では使えません」と出す。


| 項目 | 今 | この step の後 |
| --- | --- | --- |
| OS の文字起こしが使える端末 | OS の文字起こしで文字にする | 同じ |
| OS の文字起こしが使えない端末 | SenseVoice で文字にする | 準備ゲート画面に「この端末では使えません」と出し、リスニングを始めない |
| エンジンの準備 | SenseVoice のファイルが揃っているかを確かめ、Android ではダウンロードを待つ | OS の文字起こしが使えるかだけを確かめる |
| 音声 isolate（UI とは別に、音の処理だけをする作業場所） | 切り替え `useOsTranscriber` で、SenseVoice の認識器を作るかを決める | 認識器は作らない。区切った発話を UI 側へ戻すだけ |
| 使えないと分かったあと | — | 再試行しない（何度やっても結果は同じため） |


「使えない」は、prepare（OS の文字起こしが使えるかを確かめる問い合わせ）が `available: false` を返したとき。

窓口の呼び出しそのものが失敗したとき（例外）は、今と同じく失敗として再試行する。

## やること

### 音声 isolate（`stt_audio_worker.dart`）

- SenseVoice の認識器を消す
  - `_createRecognizer`、`_recognizer`、`_transcribe`、`_kRecognitionLanguage`
  - `_drainAndTranscribe` の「認識器があればその場で文字化する」側を消し、`_SegmentCaptured` を送るだけにする
- 切り替え `useOsTranscriber` と、`spawn` の `modelPath`・`tokensPath` を消す（`_WorkerStartup`・`_AudioEngine` も同じ）
- isolate の中で `sherpa.initBindings()` を呼ぶのは残す（VAD が使う）
- ファイル冒頭のコメントを、「区切った発話を UI 側へ戻し、OS の文字起こしに頼む」に直す

### エンジンの準備（`stt_providers.dart`）

- `_prepare` から、SenseVoice のファイルの確かめ（`provision()`・`_isModelReady`）とダウンロード待ち（`_waitForModelDownload`）を消す
- `_canUseOsTranscriber` を「使えなければ、使えない専用のエラーを投げる」に変える
  - 専用のエラーは新しく作る（例: `SttUnsupportedError`。理由の文字列 `detail` を持つ）
- `build` の失敗時、使えない専用のエラーなら `_scheduleRetry` を呼ばない
- `_retry` の「ダウンロードを頼み直す」部分を消し、準備のやり直し（`ref.invalidateSelf()`）だけにする

### 準備ゲート画面（`preparation_gate_page.dart`）

- フェーズ（画面に出す状態）に「使えない」を足す（例: `PreparationPhase.unsupported`）
- エンジンのエラーが使えない専用のエラーなら、このフェーズにする
- 出す文言は「この端末では使えません」。処理中ではなくお知らせなので、`ActivityDotsText` の動きは付けない（「アプリを再起動してください」と同じ扱い）

### 開発用カタログ（`stt_transcription_section.dart`）

- `SttAudioWorker.spawn` の呼び方が変わるので合わせる。SenseVoice のファイルの確かめを消し、Silero があるかだけを見る
- OS の文字起こしは UI 側から頼む窓口なので、このセクションでも、その前に `OsTranscriberChannel.prepare()` を呼んでおく

## 触るファイル

| ファイル | 場所（spike の行。step 2 の改名の前） |
| --- | --- |
| `lib/stt/stt_audio_worker.dart` | 冒頭のコメント（18〜19行目）、`_kRecognitionLanguage`（45行目）、`spawn`（89〜100行目）、`_WorkerStartup`（295〜303行目）、isolate の起動（372〜374行目）、`_AudioEngine` の生成と認識器（419〜431行目）、`_createRecognizer`（445行目〜）、`dispose` の `_recognizer?.free()`（522行目）、`_drainAndTranscribe`（567〜574行目）、`_transcribe`（586行目〜） |
| `lib/providers/stt_providers.dart` | `build` の失敗時（55行目）、`_prepare`（64〜91行目）、`_canUseOsTranscriber`（109行目〜）、`_isModelReady`（126行目〜）、`_waitForModelDownload`（134行目〜）、`_retry`（183行目〜） |
| `lib/pages/preparation_gate_page.dart` | `PreparationPhase`、`_resolvePhase`、`_buildPhaseContent` |
| `lib/pages/dev/catalog/sections/stt/stt_transcription_section.dart` | 準備（61〜76行目） |


## 確かめること

- iOS と Android で、今と同じく文字にできること
- 使えない端末の表示は、手元の実機では出せない。確かめるときは、Swift か Kotlin の prepare で一時的に `available: false` を返して `make run` し、準備ゲート画面に「この端末では使えません」が出て、再試行が始まらないことを見る（確かめたら戻す）

## この step では見ない部分

- 言語のモデルのダウンロード中の表示は step 5
- `SttModelProvisioner` の認識モデルの部分、`sttModelDownloadStateProvider`、準備ゲート画面のダウンロード表示は、使われなくなるが残す。消すのは step 6

※ step 8 までは、Android の release 版で Play が SenseVoice を自動でダウンロードし続ける（使わないのに通信と容量を使う）。準備ゲート画面にその進み具合が一瞬出ることもある。開発中だけの状態なので、そのままにする。
