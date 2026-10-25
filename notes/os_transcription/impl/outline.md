# OS の文字起こしへの切り替え 実装計画

`spike/ios-speech-transcriber` と `spike/android-speech-recognizer` で試した「OS の文字起こし」を、`main` で作り直す。

そのあと、アプリに同梱している認識モデル（SenseVoice）と、それを配るしくみを消す。

OS の文字起こしは、iOS は SpeechTranscriber（iOS 26 から使える、OS 内蔵の端末内の文字起こし）、Android は端末内の SpeechRecognizer（Android 13 から、自分で録った音を渡せる）を指す。

今と変わること:

- 今は、VAD（発話の区切りを決める係）で区切った発話を、SenseVoice（約239MB）で文字にしている。SenseVoice は iOS ではアプリに同梱し、Android では Play の自動ダウンロード（fast-follow）で配っている
- 切り替えたあとは、同じ発話を OS の文字起こしで文字にする。SenseVoice と、それを同梱する・配る・待つしくみはすべて消える
- 対応する OS は iOS 26 以上・Android 13 以上になる。OS の文字起こしが使えない端末では、リスニングを始められない

変わらないこと:

- 録音、VAD による区切り（Silero VAD と sherpa-onnx）、「.」の出し方、メモへの書き足しは今のまま

進め方:

- 1 step = 1 commit = 1つの目的
- spike は取り込まず、spike のコードを参考に main で作り直す。spike で調べるために入れたログは入れず、名前は最初から最終形にする
- ネイティブのコードが OS ごとに違う step は、iOS と Android で分ける（見出しに【iOS】【Android】【共通】を付ける）
- どの step の後でも、アプリは文字化できる状態を保つ（SenseVoice は、両 OS とも戻り先として要らなくなってから消す）
- Phase 1 の後に、しばらく使って確かめる期間を置く。Phase 2 に進むかは、その結果で決める
- 各 step は `phaseN/stepNN_名前/` に置く（計画は `plan.md`。説明資料の HTML は、頼んだときだけ作る）
- Swift・Kotlin を変えた step は、`make run` し直して確かめる

---

## 全体の流れ

```text
Phase 1  OS の文字起こしを入れる（SenseVoice は戻り先として残す）
  ↓ しばらく使って確かめる
Phase 2  OS の文字起こしだけにする        ← 一番中身のある変更
Phase 3  SenseVoice と、それを配るしくみを消す   ← 量は多いが、ほぼ削除
Phase 4  仕様書
```

---

## Phase 1 OS の文字起こしを入れる

先に Dart の土台を作り、そのあと OS ごとにネイティブの窓口を足す。

窓口を足した OS から順に、OS の文字起こしに切り替わる。

OS の文字起こしが使えない端末では、今と同じく SenseVoice で文字にする。


| step | やること |
| ---- | ------------------------------------------------------------ |
| 1    | 【共通】区切った発話を、UI 側から OS の文字起こしに頼めるようにする |
| 2    | 【iOS】SpeechTranscriber で文字にする |
| 3    | 【Android】SpeechRecognizer で文字にする |


※ step 1 は Dart だけ。ネイティブ側の窓口がまだ無いので、問い合わせは失敗し、両 OS とも SenseVoice のまま動く。

※ 窓口の返事（prepare）は、最初から `ready`（すぐ使える）・`downloading`（言語のモデルのダウンロード中）・`unsupported`（端末か言語が対応していない）の3つにする。Phase 1 では `ready` 以外はすべて SenseVoice を使い、Phase 2 で出し分ける。

### Phase 2 に進む前に確かめること

| 確かめること | iOS | Android |
| --- | --- | --- |
| 画面を消している間も文字になるか | 未確認 | 未確認 |
| 長い発話（10秒以上）の後半が抜けないか | spike では抜けていない | spike では未確認（11.6秒の発話で文字が少なめだった） |
| 「.」が出るか | spike では出る | spike では発話中の知らせは届いている。画面では未確認 |
| 普段のメモで、固有名詞・専門用語の崩れが困る程度か | 未確認 | 未確認 |
| 発熱と電池が、SenseVoice より悪くないか | 未確認 | 未確認 |

## Phase 2 OS の文字起こしだけにする

SenseVoice への戻り道を外す。ここから、OS の文字起こしが使えない端末ではリスニングを始められない。


| step | やること |
| ---- | ------------------------------------------------------------ |
| 4    | 【iOS】対応する OS の下限を、iOS 26 に上げる |
| 5    | 【Android】対応する OS の下限を、Android 13 に上げる |
| 6    | 【共通】SenseVoice への戻り道を外し、使えない端末では準備ゲート画面にそう出す |
| 7    | 【共通＋iOS】言語のモデルのダウンロード中は、準備ゲート画面にそう出して待つ |


※ step 4 の対象は Runner と Widget の両方の deployment target（`13.0`・`16.1` → `26.0`）、step 5 の対象は `minSdk`（33）。下限より古い版の確かめ（`#available` など）も消す。

※ step 6 で外す「戻り道」は、音声 isolate の中の SenseVoice の認識器と、エンジンの準備で SenseVoice のファイルを確かめて待つ部分。分かれ道は Dart の1か所なので、iOS と Android を一度に切り替える。外した後も、SenseVoice のファイルとそれを配るしくみは残っている（使われないだけ）。消すのは Phase 3。

※ step 7 で変わるネイティブは iOS だけ。Android は step 3 から、ダウンロード中なら `downloading` を返している。

## Phase 3 SenseVoice と、それを配るしくみを消す

使われなくなったものを消す。どれも削除が中心で、動きは変わらない。

どの step の後でもビルドが通るよう、使う側（Dart）から先に消し、使われる側（iOS・Android のネイティブ・スクリプト）を後に消す。


| step | やること |
| ---- | ------------------------------------------------------------ |
| 8    | 【共通】Dart から、認識モデルの置き場所とダウンロードの扱いを消す |
| 9    | 【iOS】同梱した認識モデルを消す |
| 10   | 【Android】Play の自動ダウンロードを消す |
| 11   | 【共通】モデルの取得スクリプトを消す |


※ step 8 で消すのは、`SttModelProvisioner` の認識モデルの部分、`asset_pack_delivery.dart`、ダウンロードの進み具合（`sttModelDownloadStateProvider`）と準備ゲート画面のダウンロード表示、開発用カタログの「モデル配置」。

※ step 9 で消すのは、`ios/Runner/Models/`（SenseVoice 本体と tokens）、`SttModelChannel.swift`、Xcode への登録、`place_ios_models.sh`、`register_ios_files.rb`。

※ step 10 で消すのは、アセットパック `android/stt_models`、`asset-delivery` ライブラリ、`AssetPackDeliveryChannel.kt`、`place_android_*.sh`。Android の release 実行が AAB（Google Play に渡す形）を経由する理由も無くなるので、`run_on_device.sh` と `install_android_bundle.sh` も見直す。`asset-delivery` が自動で足していた `INTERNET` 権限も無くなる。

※ step 11 で消すのは、`download_stt_model.sh`、`scripts/lib/stt_model_constants.sh`、Makefile の `models`、`.gitignore` のモデルの行。

※ 残すもの: `sherpa_onnx` と Silero VAD（`assets/models/silero_vad.onnx`）。`SttModelProvisioner` は、Silero を端末へコピーする係として残る。

## Phase 4 仕様書


| step | やること |
| ---- | ------------------------------------------------------------ |
| 12   | 【共通】仕様書を直す |


※ 対象は `notes/specs/` の `overview.md`・`permission_flow.md`・`listening_flow.md`・`preparation_gate.md`。仕様書は無時制で書く（「OS の文字起こしに切り替えた」ではなく、初めからそう作った書き方にする）。
