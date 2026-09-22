# モデル・設定・使い方

調査日: 2026-09-22。[入口](README.md)

## 1. Small とは何か

公開されている SenseVoiceSmall は、中国語（普通話）、広東語、英語、日本語、韓国語を扱う音声認識モデルです。文字起こしのほか、言語・感情・音声イベントのラベルを出します。**話者を特定するモデルではありません。** 公式リポジトリが案内する話者分離は、別のモデルを組み合わせた構成です。[公式モデルカード][card]・[公式利用ガイド][readme]

Small は非自己回帰の CTC 系モデルで、論文のパラメータ数は **234M**。論文に登場する Large は別の構造・規模であり、「50言語以上」などの説明を Small に持ち込まないようにします。論文の10秒音声を約70msで処理する値は A800 GPU の実験で、スマートフォンの表示遅延を表す数値ではありません。[論文 §2.2・Table 7][paper]

### <a id="variants"></a>モデルの日付と中身

| 候補 | 今回の理解 | momeo での扱い |
|---|---|---|
| 2024-07-17 int8 | 現行の5言語モデル。約239MBの ONNX 本体 | 調整の基準として維持 |
| 同系統の非量子化 ONNX | 精度差の切り分けに使える比較対象 | int8 が誤りの主因かを調べるときだけ。RAM増加を別に確認 |
| 2025-09-09 int8 | 21.8k時間の広東語データで微調整したモデル。句読点非対応との公式説明 | 日本語向けの単純な更新先とはしない |
| FunASR や派生プロジェクトの新モデル | 名前に SenseVoice が含まれても学習・対応言語・入出力が同一とは限らない | 元の Small と区別して確認 |

2025版の位置づけは [sherpa のモデル一覧][pretrained] に明記されています。重みの日付、ONNX の変換方法、推論ライブラリの版は、それぞれ別に記録する必要があります。

## 2. 現在の momeo の設定

| 層 | 設定 | 現在値 |
|---|---|---|
| モデル | 配布物 | `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2` |
| モデル | 本体 / tokens | `model.int8.onnx` 239,233,841 bytes / `tokens.txt` 315,894 bytes |
| 実行 | Dart / iOS native | `sherpa_onnx` 1.13.8 |
| 実行 | provider / decoding | 未指定。Dart既定は `cpu` / `greedy_search` |
| ASR | `language` | `''` = 自動判定 |
| ASR | `useInverseTextNormalization` | `true` |
| ASR | `numThreads` | `1` |
| 録音 | 入力 | PCM16 little endian、16kHz、mono |
| VAD | モデル / threads | Silero / `1` |
| VAD | `threshold` | `0.35` |
| VAD | `minSilenceDuration` | `1.5` 秒 |
| VAD | `minSpeechDuration` | `0.25` 秒 |
| VAD | `maxSpeechDuration` | `30.0` 秒。厳密な強制分割ではない |
| VAD | 窓 / buffer | 512 samples = 32ms / 60秒指定 |
| 出力 | 保存前処理 | `trim()` のみ |

確認元: [音声worker](../../../lib/stt/stt_audio_worker.dart)、[録音pipeline](../../../lib/stt/stt_listening_pipeline.dart)、[保存処理](../../../lib/providers/listening_providers.dart)、[配布定数](../../../scripts/lib/stt_model_constants.sh)、[pubspec](../../../pubspec.yaml)、[Dart 1.13.8 API][dart]。

取得書庫の SHA256 は `7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e`。これは配布定数に固定された値で、今回モデルを再取得・照合したという意味ではありません。

現在は SenseVoice 固定です。採用判断文書の `--dart-define=STT_MODEL=sensevoice` は試用段階の説明で、今の切替方法ではありません。

## 3. 何を変更できるか

| 設定・手法 | この構成での意味 | 比較するときの注意 |
|---|---|---|
| `language=''` / `auto` / `ja` / `en` / `zh` / `ko` / `yue` | 言語条件。モデルに対応する言語IDが必要 | 特に `yue` は ONNX の metadata と対応状況も確認。言語固定は文字種の禁止規則ではない |
| `useInverseTextNormalization` | ITN と句読点を含む出力スタイルの条件 | 認識内容も変わり得る |
| ASR `numThreads` | CPU推論の並列度 | 速さ、発熱、電力は別々の結果。1→2を試すなら同じ端末・ビルドで |
| VAD のしきい値・時間 | 認識器に渡す音声の範囲と確定タイミング | ASR の内部設定ではない。連続PCMで比較する |
| FP32 / int8 | モデルの数値表現 | 同じ元checkpoint・変換条件で比べる |
| `provider` | 利用する推論バックエンド | モデル・端末・配布バイナリの対応が必要。文字列の変更だけで高速化を保証しない |
| `decodingMethod` / `maxActivePaths` | 共通APIには存在 | **v1.13.8 の SenseVoice は greedy_search のみ**。beamへ変更する調整はできない |
| `hotwordsFile` / `hotwordsScore` / `blankPenalty` | 他方式も含む共通APIの設定 | この SenseVoice 経路で有効な調整項目とは扱わない |
| LLM の temperature / prompt | この Small の通常推論に対応する設定なし | WhisperやLLMのチューニング記事を流用しない |

対応範囲は [v1.13.8 SenseVoice実装][impl] と [モデル設定の検証処理][config] で確認。共通の `OfflineRecognizerConfig` にフィールドがあることと、選んだモデルで処理されることは別です。

### <a id="itn"></a>ITN が特に重要な理由

ITN は、読み上げ表現を数字等の書き言葉へ寄せる inverse text normalization です。SenseVoice は ITN 有効・無効の条件を**推論の入力**に入れます。認識済み文字列へ句読点を付けるだけの別工程ではありません。[モデル実装][model]・[sherpa実装][impl]

したがって、`16002年` を調べるときは、同じPCMを `true` / `false` で認識して、数字の値、周囲の語、反復・言い直し、句読点を別々に見ます。**OFFで数字が直ることは未確認**です。OFFなら「千六百」などの表現になる可能性もあるため、文字列の一致と数値の一致を分けます。句読点だけを消す表示処理とも区別します。

## 4. momeo と同じ系統で試す最小設定

次は現在の生成処理に対応する Dart の設定例です。パスは配置済みのモデルと tokens を渡します。設定比較では、ASRだけを比較する限り、入力PCM・VAD区間は固定します。

```dart
final config = sherpa.OfflineRecognizerConfig(
  model: sherpa.OfflineModelConfig(
    senseVoice: sherpa.OfflineSenseVoiceModelConfig(
      model: modelPath,
      language: '', // momeo の自動判定
      useInverseTextNormalization: true,
    ),
    tokens: tokensPath,
    numThreads: 1,
    debug: kDebugMode,
  ),
);
```

`createStream → acceptWaveform → decode → getResult → stream.free()` を1区間ごとに行い、認識器本体は使い回します。新しい設定を比較する際は、その設定で生成した認識器を使います。アプリでは毎回の発話で本体をロードし直さない構成がすでにできています。[現行worker](../../../lib/stt/stt_audio_worker.dart)

## 5. FunASR の記事を読むための対応表

FunASR は公式 Python の利用・学習経路です。momeo は sherpa の ONNX 経路なので、Python のオプションをそのまま Dart に追加することはできません。

| FunASR の表記 | 意味 | momeo に対応させると |
|---|---|---|
| `language="auto"` | 言語自動判定 | 現在の `language: ''` |
| `use_itn=True` | ITN条件 | `useInverseTextNormalization: true` |
| `vad_model="fsmn-vad"` | 外部VADを組み合わせる | 現在は Silero。別モデルへの変更になる |
| `max_single_segment_time=30000` | FSMN側の区間設定、単位ms | Sileroの `maxSpeechDuration` と同じ仕様ではない |
| `merge_vad` / `merge_length_s` | 小さなVAD区間を結合 | momeoに同名のスイッチなし。待ち時間・カード粒度を伴う実装変更 |
| `batch_size_s` | バッチに入れる音声の総秒数の目安 | 1発話の上限や無音待ち時間ではない |
| `batch_size` | 同時処理する入力数 | 常時録音の低遅延化と同義ではない |
| `rich_transcription_postprocess` | 特殊タグの整形・除去等 | 日本語内部空白の全面修正機能とは確認できない |
| `output_timestamp` | Python側のアラインメント出力 | sherpa の時刻配列とは形式・生成方法が違う |
| `ban_emo_unk` | 感情タグの扱い | 日本語ASR精度を上げる一般設定ではない |

参照: [公式推論例][readme]、[FunASR後処理のソース][postprocess]。公式READMEの短い音声向け直接推論は30秒以下を案内しています。momeoの長区間については [アプリ側の区切り](app-best-practices.md#segmentation) を参照。

Python で補助実験する場合は、公式リポジトリの特定revisionと、動作確認した FunASR / PyTorch / モデルrevisionを一組で保存します。`remote_code="./model.py"` を使う例では、そのファイルも実装の一部です。Pythonだけを更新してもローカルの `model.py` は更新されません。**Pythonで得た改善は、採用ONNXとDart経路で再確認するまで本番の改善とは扱いません。**

[card]: https://huggingface.co/FunAudioLLM/SenseVoiceSmall
[readme]: https://github.com/QwenAudio/SenseVoice/blob/ea15219509625e5d4c5143c37c86970135886b5d/README.md
[paper]: https://arxiv.org/html/2407.04051v2
[pretrained]: https://k2-fsa.github.io/sherpa/onnx/sense-voice/pretrained.html
[dart]: https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/flutter/sherpa_onnx/lib/src/offline_recognizer_config.dart
[impl]: https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/offline-recognizer-sense-voice-impl.h
[config]: https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/offline-sense-voice-model-config.cc
[model]: https://github.com/QwenAudio/SenseVoice/blob/ea15219509625e5d4c5143c37c86970135886b5d/model.py
[postprocess]: https://github.com/modelscope/FunASR/blob/main/funasr/utils/postprocess_utils.py
