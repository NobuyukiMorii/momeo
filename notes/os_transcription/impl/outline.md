# OS の文字起こしへの切り替え 実装計画

`spike/ios-speech-transcriber` と `spike/android-speech-recognizer` で試した「OS の文字起こし」を `main` に入れ、アプリに同梱している認識モデル（SenseVoice）と、それを配るしくみを消す。

OS の文字起こしは、iOS は SpeechTranscriber（iOS 26 から使える、OS 内蔵の端末内の文字起こし）、Android は端末内の SpeechRecognizer（Android 13 から、自分で録った音を渡せる）を指す。

今と変わること:

- 今は、VAD（発話の区切りを決める係）で区切った発話を、SenseVoice（約239MB）で文字にしている。SenseVoice は iOS ではアプリに同梱し、Android では Play の自動ダウンロード（fast-follow）で配っている
- 切り替えたあとは、同じ発話を OS の文字起こしで文字にする。SenseVoice と、それを同梱する・配る・待つしくみはすべて消える
- 対応する OS は iOS 26 以上・Android 13 以上になる。OS の文字起こしが使えない端末では、リスニングを始められない

変わらないこと:

- 録音、VAD による区切り（Silero VAD と sherpa-onnx）、「.」の出し方、メモへの書き足しは今のまま

進め方:

- 1 step = 1 commit = 1つの目的
- お手本は2つの spike のコード（`spike/android-speech-recognizer` は `spike/ios-speech-transcriber` の続きなので、両方の変更が入っている）
- どの step の後でも、アプリは文字化できる状態を保つ（SenseVoice は、戻り先として要らなくなってから消す）
- Phase 1 の後に、しばらく使って確かめる期間を置く。Phase 2 に進むかは、その結果で決める
- 各 step は `phaseN/stepNN_名前/` に置く（計画は `plan.md`。説明資料の HTML は、頼んだときだけ作る）
- Swift・Kotlin を変えた step は、`make run` し直して確かめる

---

## 全体の流れ

```text
Phase 1  OS の文字起こしを main に入れる（SenseVoice は戻り先として残す）
  ↓ しばらく使って確かめる
Phase 2  OS の文字起こしだけにする        ← 一番中身のある変更
Phase 3  SenseVoice と、それを配るしくみを消す   ← 量は多いが、ほぼ削除
Phase 4  仕様書
```

---

## Phase 1 OS の文字起こしを main に入れる

spike の2つのコミットを取り込み、調べるために入れた部分を片付ける。

OS の文字起こしが使えない端末では、今と同じく SenseVoice で文字にする。


| step | やること |
| ---- | ------------------------------------------------------------ |
| 1    | 2つの spike のコミットを main に取り込む |
| 2    | 調べるために入れたログを片付け、窓口の名前を OS 共通にする |


※ step 1 の取り込みは、main に枝分かれが無いので fast-forward（コミットをそのまま足すだけの取り込み）になる。git の操作はユーザーが行う。

※ step 2 で片付けるのは、Android の途中経過の受け取り（`EXTRA_PARTIAL_RESULTS`）と `Log.d`、発話ごとに出している `debugPrint`。窓口は、Android でも `SpeechTranscriberChannel` という名前で動いているので、OS 共通の名前にする。

### Phase 2 に進む前に確かめること

| 確かめること | iOS | Android |
| --- | --- | --- |
| 画面を消している間も文字になるか | 未確認 | 未確認 |
| 長い発話（10秒以上）の後半が抜けないか | 抜けていない | 未確認（11.6秒の発話で文字が少なめだった） |
| 「.」が出るか | 出る | 発話中の知らせは届いている。画面では未確認 |
| 普段のメモで、固有名詞・専門用語の崩れが困る程度か | 未確認 | 未確認 |
| 発熱と電池が、SenseVoice より悪くないか | 未確認 | 未確認 |

## Phase 2 OS の文字起こしだけにする

SenseVoice への戻り道を外す。ここから、OS の文字起こしが使えない端末ではリスニングを始められない。


| step | やること |
| ---- | ------------------------------------------------------------ |
| 3    | 対応する OS の下限を、iOS 26・Android 13 に上げる |
| 4    | SenseVoice への戻り道を外し、使えない端末では準備ゲート画面にそう出す |
| 5    | 言語のモデルのダウンロード中は、準備ゲート画面にそう出して待つ |


※ step 3 の対象は、iOS は Runner と Widget の両方の deployment target（`13.0`・`16.1` → `26.0`）、Android は `minSdk`（33）。`#available(iOS 26.0, *)` と、Android の版の確かめは不要になる。

※ step 4 で外す「戻り道」は、音声 isolate の中の SenseVoice の認識器と、エンジンの準備で SenseVoice のファイルを確かめて待つ部分。外した後も、SenseVoice のファイルとそれを配るしくみは残っている（使われないだけ）。消すのは Phase 3。

※ step 5 の前は、言語のモデルが端末に無いとき、iOS は準備の中で黙ってダウンロードを待ち（画面はアプリ名のまま）、Android はダウンロードを頼むだけで、その起動では使えない（次の起動から使える）。

## Phase 3 SenseVoice と、それを配るしくみを消す

使われなくなったものを消す。どれも削除が中心で、動きは変わらない。

どの step の後でもビルドが通るよう、使う側（Dart）から先に消し、使われる側（iOS・Android のネイティブ・スクリプト）を後に消す。


| step | やること |
| ---- | ------------------------------------------------------------ |
| 6    | Dart から、認識モデルの置き場所とダウンロードの扱いを消す |
| 7    | iOS の同梱を消す |
| 8    | Android の自動ダウンロードを消す |
| 9    | モデルの取得スクリプトを消す |


※ step 6 で消すのは、`SttModelProvisioner` の認識モデルの部分、`asset_pack_delivery.dart`、ダウンロードの進み具合（`sttModelDownloadStateProvider`）と準備ゲート画面のダウンロード表示、開発用カタログの「モデル配置」。

※ step 7 で消すのは、`ios/Runner/Models/`（SenseVoice 本体と tokens）、`SttModelChannel.swift`、Xcode への登録、`place_ios_models.sh`。

※ step 8 で消すのは、アセットパック `android/stt_models`、`asset-delivery` ライブラリ、`AssetPackDeliveryChannel.kt`、`place_android_*.sh`。Android の release 実行が AAB（Google Play に渡す形）を経由する理由も無くなるので、`run_on_device.sh` と `install_android_bundle.sh` も見直す。`asset-delivery` が自動で足していた `INTERNET` 権限も無くなる。

※ step 9 で消すのは、`download_stt_model.sh`、`scripts/lib/stt_model_constants.sh`、Makefile の `models`、`.gitignore` のモデルの行。

※ 残すもの: `sherpa_onnx` と Silero VAD（`assets/models/silero_vad.onnx`）。`SttModelProvisioner` は、Silero を端末へコピーする係として残る。

## Phase 4 仕様書


| step | やること |
| ---- | ------------------------------------------------------------ |
| 10   | 仕様書を直す |


※ 対象は `notes/specs/` の `overview.md`・`listening_flow.md`・`preparation_gate.md`。仕様書は無時制で書く（「OS の文字起こしに切り替えた」ではなく、初めからそう作った書き方にする）。
