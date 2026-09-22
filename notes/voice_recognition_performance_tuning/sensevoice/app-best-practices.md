# アプリでの使い方と確認点

調査日: 2026-09-22。[入口](README.md)

## 1. 現在の処理と、調整が効く場所

```mermaid
flowchart LR
  A[マイク PCM16 / 16kHz] --> B[音声 isolate の受信待ち]
  B --> C[Silero VAD]
  C --> D[1区間の SenseVoice 推論]
  D --> E[textを取得]
  E --> F[trimして保存]
  F --> G[カード表示・検索]
```

現行は ASR と VAD を同じ isolate で順に実行しています。本体モデルを使い回し、区間ごとの stream を解放する構成はできています。調整時は、収音、区切り、ASR、表示・検索のどこを変えるかを明示します。[worker](../../../lib/stt/stt_audio_worker.dart)・[pipeline](../../../lib/stt/stt_listening_pipeline.dart)

## 2. <a id="segmentation"></a>長い音声をどう区切るか

SenseVoiceSmall は、渡された区間全体を処理する非ストリーミングモデルです。VADで発話を確定してから認識する方式は、公式 sherpa のマイク利用例にもあります。[公式マイク例][pretrained]

公式Pythonの直接推論例は30秒以下を案内しています。一方、これは「31秒を渡したら必ず失敗する」というモデルの固定上限の証明ではありません。**長区間を無制限に渡さず、実際に渡す長さを把握する**という設計上の目安として扱います。[公式ガイド][readme]

### momeo の30秒指定で保証されていないこと

sherpa 1.13.8 の VAD は、上限超過時に無音判定の待ちを0.1秒、しきい値を0.90へ変更して区切れやすくします。必ずその場で分割する処理ではありません。bufferも必要に応じて拡張されます。[VAD実装][vad]・[circular buffer][buffer]

[既存S5](../spike/segmentation.md) でも30秒指定を超える区間が確認されています。これは今回見つけた新しい精度不具合ではなく、**既知の区切り仕様が非ストリーミングの SenseVoice にも引き継がれた**点が重要です。

長文の崩れや遅延が現れたときの候補は、次の順が考えられます。

1. 実際の区間長・推論時間を見て、長い区間だけで悪化しているか確認する。
2. VAD の `maxSpeechDuration` の比較と、アプリ側で厳密に長さを制限する比較を分ける。前者だけでは上限を保証しない。
3. 厳密に切る場合は、語の途中を切る影響、少量の重複音声、重複テキストの扱いを同時に設計する。

公式の長音声用補助スクリプトには、30秒窓・2秒重複を使い、各窓の生出力を残す方式があります。これはファイル処理の参考例であり、momeo のリアルタイム設定として最適な値ではありません。[long_audio_no_vad.py][long-audio]

重複区間を単純に文字列で削ると、本人が本当に繰り返した語まで消す場合があります。小さな重複を入れる案を試すなら、生音声上の範囲と生出力を残し、文の途中・語の反復で確かめます。既存の確定カードを書き換えない方針との整合も必要です。

## 3. 待ち時間・電池・メモリを分けて考える

発話終了から表示までの時間は、おおよそ **VADの終端待ち + 未処理音声の待ち + 推論 + 保存・UI処理**です。現在の `minSilenceDuration=1.5秒` があるため、ASRだけが数百ms速くなっても、表示までの全体が同じ比率で速くなるとは限りません。

また、発話開始から見ると発話そのものの長さも加わります。長い発話を分割せず認識する場合、モデルの処理速度だけでは途中表示の遅さを解消できません。

現行workerは `decode()` 中に次のPCMを処理できず、送り側は応答を待たず送信します。その間、後続PCMが isolate の受信待ちに溜まり得ます。**現行SenseVoiceで実際に詰まったことを示す新規測定はありません。** 長文・発話率の高い環境を調べるときの観測点です。

推奨する観測値は、認識区間秒数、decode時間、発話終端から保存までの時間、入力された音声時刻と処理済み音声時刻の差です。単なるキュー件数より「何秒ぶん遅れているか」が分かると判断しやすくなります。長時間録音を無条件に捨ててキューを抑える処理は、メモの欠落という別の問題を生みます。

ASR `numThreads` は1→2の比較候補です。ただし早く終わっても電力が下がるとは限りません。公式のRK3588測定値は端末が違うため、iPhone/Pixelへ外挿しません。[公式速度比較][pretrained]

既存RAM値も条件を区別します。固定wav専用アプリでは NeMo 1,393MB / SenseVoice 778MB（約44%減）、本番Androidの691MBは起動直後の別測定です。モデルファイル655,542,604→239,233,841 bytesの約64%減と、RAMを同じ「半分以下」とまとめないようにします。[採用記録](../decision/adopt-sensevoice.md)

## 4. <a id="restart"></a>停止・再始動で VAD の状態をどう扱うか

現行 `startListening()` は同じVADを使い回す際に `clear()` を呼び、停止時には `flush()` を呼びます。watchdog の録音再始動も、停止から開始への経路を通ります。

native 1.13.8 では次の違いがあります。

| 操作 | 実装上の役割 |
|---|---|
| `Clear()` | 確定済みsegmentのqueueを消す |
| `Flush()` | 末尾区間を押し出し、区間・bufferの位置を更新する |
| `Reset()` | モデル内部状態や残り窓等も初期化する |

`Flush()` は Silero のLSTM状態等を全面的には初期化しません。Dart 1.13.8 には `reset()` もあります。[VAD本体][vad]・[Silero状態管理][silero]・[Dart VAD API][dart-vad]

**これだけで現在のコードが誤認を起こすとは断定できません。** 同一の連続音声を処理し続ける場面では状態維持に意味があります。一方、録音に空白期間があったあと、新しいセッションとして再開するなら、状態が残ることの影響を確認できます。

試す対象は、発話中に停止→再開→短い「はい」、watchdog再始動の前後、無音で停止→再開です。`flush → 結果を回収 → reset → 新しい録音` の候補を、現行と同一の入力列で比較します。通常のOS割り込み `pauseResume` がすべてこの再生成経路を通るとは限らず、別に扱います。今回コードは変更していません。

## 5. 出力を捨てずに原因を切り分ける

Dartの結果には `text` 以外に `tokens`、`timestamps`、`lang`、`emotion`、`event` があります。momeoが現在使っているのは `text` だけです。[Dart結果API][dart-result]・[native結果変換][impl]

開発用の比較でこれらを残せば、別言語として認識されたのか、BGM等を含むと判断されたのか、どこで空白が生じたかを追いやすくなります。ただし、感情・イベントラベルは正解保証でも認識confidenceでもありません。`Speech` 以外だからという理由だけで音声を捨てる仕組みは、声と環境音が重なる場面で欠落につながり得ます。

`timestamps` は sherpa のtoken出現位置に基づく秒値で、必ずしも単語の開始終了時刻ではありません。Python の `output_timestamp` と同じ仕様だと仮定せず、単位、tokenとの対応、segment内の相対時刻かを確認して使います。

さらに、native SenseVoice実装は ONNX Runtime 例外をログへ出して空結果のまま戻る経路があります。**空文字だけを数えると、正常な無文字出力と推論の失敗を区別できません。** 空出力が問題になった比較では、nativeログも確認します。[例外処理を含む実装][impl]

## 6. 入力・短い発話・ノイズ

公式frontendは16kHzを前提とします。[公式config][hf-config]。momeoは16kHz monoのPCM16を要求し、`32768` で割って Float32 にしています。別の録音素材を使う場合は、サンプルレートのラベルを付け替えるだけでなく、必要な変換を実際に行います。

相づちを拾うために `minSpeechDuration` を下げる、語頭を残すために前余白を足す、といった案には、生活音を拾う、カードが細切れになるという交換条件があります。旧モデルのS5では threshold 0.35が選ばれましたが、SenseVoiceとの組合せの最適値ではありません。[既存S5](../spike/segmentation.md)

ノイズ抑制、AGC、エコー除去、入力音量の変更も、症状があるときの比較候補です。小声や子音を削る可能性もあるため、強い処理を一律に足す推奨値は今回得られませんでした。現在の録音処理と同じ実機経路で、近距離・遠距離・Bluetoothなど問題の出た条件を固定して比べます。

## 7. 量子化と追加学習

### 量子化が原因かを先に確かめる

int8をやめれば日本語が改善するとの実証は、今回得られていません。疑う場合は、同じ元モデルのFP32とint8に同一音声を渡して比較します。先にPCで文字列差を調べ、意味のある改善がある場合にモバイルのRAMと速度を確認すると、小さく切り分けられます。

sherpa専用exporterは、言語ID・CMVN等のmetadataとtokensを用意し、MatMulの量子化にQUInt8を指定しています。コード内にはQInt8だとC++実行で問題が出る旨の注意があります。これは当該exporterの条件であり、すべてのモデルの量子化に一般化しません。[sherpa exporter][exporter]

### 日本語の追加学習は可能だが、設定変更より大きい仕事

公式には [fine-tuningのスクリプト][finetune] があり、日本語の言語ラベルを含む学習経路があります。ただし、日本語の少量個人音声に必要な時間・GPU・改善量の保証されたレシピは確認できませんでした。

FunASRの [SenseVoice dataset実装][dataset] は、言語ラベル省略時に中国語、ITNラベル省略時に非ITNを既定値とします。日本語wavと正解文だけを入れれば十分、と考えず、言語・感情・イベント・ITNのラベルと表記方針をそろえます。学習例のbatch size、epoch、学習率をそのまま最適値として採用しません。

追加学習を検討するなら、固有名詞や日英表記など何を改善したいかを先に固定し、別の録音・文を検証用に残します。日本語を改善して英語・中国語・短い相づちを悪化させていないかも見る必要があります。

その後の経路は **学習済みcheckpoint → sherpa用FP32 ONNX → int8 ONNX → 実機** です。各段階で同じ音声を比較します。公式 [export.py][upstream-export] の例は既存ONNXがあるとexportを省略するため、学習後に古いファイルを測らないよう、入力checkpoint・出力先・ハッシュを記録します。FunASR用ONNXをそのままmomeoのファイルに置き換えられるとは仮定しません。

## 8. 途中表示・話者分離を広げる場合

sherpaには非ストリーミングモデルで途中結果を出す例があり、第三者にはモデル側のattention処理を変えた [streaming-sensevoice][streaming] もあります。どちらも、今の区間確定後1回認識とは計算量や精度条件が変わります。

momeoの確定カードを変えない方針に合わせるなら、途中表示を導入する場合も「まだ確定していない表示」と「保存する結果」を分ける設計が候補です。推論回数が増える分、電池・発熱を改めて確認します。

話者分離は別モデルの組合せです。Smallの感情やイベントラベルから誰が話したかは判定できません。公式PythonにはCAM++等との構成例がありますが、現行Dartの設定追加だけで同じ機能が手に入るわけではありません。[公式ガイド][readme]

[pretrained]: https://k2-fsa.github.io/sherpa/onnx/sense-voice/pretrained.html
[readme]: https://github.com/QwenAudio/SenseVoice/blob/ea15219509625e5d4c5143c37c86970135886b5d/README.md
[long-audio]: https://github.com/QwenAudio/SenseVoice/blob/ea15219509625e5d4c5143c37c86970135886b5d/long_audio_no_vad.py
[vad]: https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/voice-activity-detector.cc
[buffer]: https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/circular-buffer.cc
[silero]: https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/silero-vad-model.cc
[dart-vad]: https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/flutter/sherpa_onnx/lib/src/vad.dart
[dart-result]: https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/flutter/sherpa_onnx/lib/src/offline_recognizer.dart
[impl]: https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/offline-recognizer-sense-voice-impl.h
[hf-config]: https://huggingface.co/FunAudioLLM/SenseVoiceSmall/blob/main/config.yaml
[exporter]: https://github.com/k2-fsa/sherpa-onnx/blob/master/scripts/sense-voice/export-onnx.py
[finetune]: https://github.com/QwenAudio/SenseVoice/blob/ea15219509625e5d4c5143c37c86970135886b5d/finetune.sh
[dataset]: https://github.com/modelscope/FunASR/blob/main/funasr/datasets/sense_voice_datasets/datasets.py
[upstream-export]: https://github.com/QwenAudio/SenseVoice/blob/ea15219509625e5d4c5143c37c86970135886b5d/export.py
[streaming]: https://github.com/pengzhendong/streaming-sensevoice
