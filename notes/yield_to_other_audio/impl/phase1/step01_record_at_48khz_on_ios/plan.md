# Step 1 iOS は 48kHz で録り、16kHz に落としてから渡す

## 目的

momeo の録音中に、他のアプリの音がこもらないようにする（iOS）。

iOS では、録音に指定したサンプリングレートが iPhone 全体の再生にも効く。16kHz で録ると、YouTube などの音まで 16kHz に落ち、8kHz より上の音が消えてこもる。


| 項目 | 今 | この step の後 |
| --- | --- | --- |
| iOS で録るレート | 16kHz | 48kHz |
| 音声 isolate へ渡すレート | 16kHz | 16kHz（変わらない） |
| 録音中の他のアプリの音（iPhone のスピーカー） | こもる | こもらない |
| Android | 16kHz で録る | 変わらない |


Bluetooth イヤホンのこもり（通話用の方式 HFP）は、この step では直らない（step 2・5 で直す）。

## やること

- 48kHz の PCM16 を 16kHz の PCM16 に落とす係 `SttDownsampler` を足す（8kHz より上を削ってから、3サンプルに1つ残す。チャンクの境目で途切れないよう、直前の音を持ち越す）
- iOS だけ、録音を 48kHz で開く（`RecordConfig` は端末で値が変わるので `const` から `final` にする）
- iOS だけ、届いたチャンクを 16kHz に落としてから音声 isolate へ渡す
- 録音を開き直すたびに、持ち越した音を捨てる

VAD・認識モデル・音声 isolate は 16kHz のまま触らない。仕様書の認識パイプラインの図は step 10 で直す。

## 参照する `spike/yield-to-other-audio` のコード

spike には、このあとの step の変更も入っているので、レートと変換に関わる部分だけを見る。


| ファイル | 場所 |
| --- | --- |
| `lib/stt/stt_downsampler.dart` | ファイル全体（117行）。フィルタの設定（20〜21行目）、`inputSampleRate`（30行目）、`reset`（43行目）、`convert`（51行目〜）、`_buildLowPassCoefficients`（96行目〜） |
| `lib/stt/stt_listening_pipeline.dart` | `_kSampleRate`・`_kRecordSampleRate`（30〜34行目）、`sampleRate`（70行目）、`_downsampler`（123行目）、`_listenToAudio` の `reset`（310行目）、`_onAudioChunk` の変換（323行目〜） |


spike では `RecordConfig` を `_buildRecordConfig` で作っている（Bluetooth のマイクを使う・使わないの2通りを作るため。step 5）。この step では今の `_kRecordConfig` の `sampleRate` を替えるだけにする。

フィルタは spike で数値を確かめ済み（4kHz まで −0.0dB、7kHz で −6dB、8kHz で −29dB、9kHz より上は −64dB 以下。チャンクの切り方を変えても一度に変換したときと一致。1分ぶんの変換が約 47ms）。
