# 出典と調査範囲

参照日: **2026-09-22**。外部の仕様は原論文、公式モデルカード、公式コード・ドキュメントを中心に確認しました。利用事例は作者自身のREADME、問題報告は投稿者本人のIssueを参照しています。

## 版の基準

| 対象 | 調査時の基準 |
|---|---|
| momeo | `main` / `c7e386e`。今回の新規文書を追加する前のHEAD |
| sherpa-onnx | **v1.13.8**。現行アプリと同じ版のnative/Dartコードを参照 |
| 採用モデル | Small int8、2024-07-17。詳細は [設定表](model-and-settings.md) |
| QwenAudio/SenseVoice | mainのHEADは **`ea15219509625e5d4c5143c37c86970135886b5d`**、commit日2026-09-10。GitHub APIで確認 |
| 論文 | arXiv **2407.04051v2**、2024-07-09 |
| その他のmain/master・Web資料 | 参照日時点。将来の変更に追随するリンクであり、採用モデルと同じ版とは限らない |

## 1. モデルと公式の使い方

| 出典 | 本調査で確認したこと |
|---|---|
| [SenseVoice公式リポジトリ](https://github.com/QwenAudio/SenseVoice) | 公開モデルと提供機能の入口 |
| [固定revisionの英語README](https://github.com/QwenAudio/SenseVoice/blob/ea15219509625e5d4c5143c37c86970135886b5d/README.md) | FunASRでの推論、VAD、ITN、長音声、話者分離との組合せ |
| [公式日本語README](https://github.com/QwenAudio/SenseVoice/blob/ea15219509625e5d4c5143c37c86970135886b5d/README_ja.md) | 日本語の導入・学習説明 |
| [公式中国語README](https://github.com/QwenAudio/SenseVoice/blob/ea15219509625e5d4c5143c37c86970135886b5d/README_zh.md) | 設定名・学習形式の原文確認 |
| [Hugging Faceモデルカード](https://huggingface.co/FunAudioLLM/SenseVoiceSmall) | Smallの公開checkpoint |
| [モデルconfig](https://huggingface.co/FunAudioLLM/SenseVoiceSmall/blob/main/config.yaml) | 16kHz frontendと学習設定の区別 |
| [FunAudioLLM論文v2](https://arxiv.org/html/2407.04051v2) | Small/Large、234M、言語別指標、GPUの速度条件 |
| [公式model.py](https://github.com/QwenAudio/SenseVoice/blob/ea15219509625e5d4c5143c37c86970135886b5d/model.py) | 言語・ITN条件、CTC処理、Pythonのtimestamp |

## 2. sherpa-onnxの適用範囲

以下のコードリンクは、exporter以外は **v1.13.8固定**です。

| 出典 | 本調査で確認したこと |
|---|---|
| [SenseVoiceモデル一覧](https://k2-fsa.github.io/sherpa/onnx/sense-voice/pretrained.html) | 2024版、広東語向け2025版、ITN例、マイク利用、CPU速度 |
| [広東語版の開発元](https://huggingface.co/ASLP-lab/WSYue-ASR) | 新しい日付のモデルの用途 |
| [SenseVoice recognizer](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/offline-recognizer-sense-voice-impl.h) | greedy限定、ITN stream option、結果変換、空結果へ戻る例外処理 |
| [SenseVoice model config](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/offline-sense-voice-model-config.cc) | 言語設定の検証 |
| [CTC greedy decoder](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/offline-ctc-greedy-search-decoder.cc) | 共通APIにある設定が、このdecodeで使われるとは限らない |
| [SymbolTable](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/symbol-table.cc) | SentencePieceの空白記号の扱い |
| [VAD本体](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/voice-activity-detector.cc) | 区間長超過時の動作、Clear/Flush/Reset |
| [Silero状態管理](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/silero-vad-model.cc) | VAD内部状態 |
| [circular buffer](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/circular-buffer.cc) | 容量超過時の拡張 |
| [Dart config](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/flutter/sherpa_onnx/lib/src/offline_recognizer_config.dart) | 既定値と公開設定 |
| [Dart結果API](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/flutter/sherpa_onnx/lib/src/offline_recognizer.dart) | text以外の結果項目 |
| [Dart stream API](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/flutter/sherpa_onnx/lib/src/offline_stream.dart) | setOption |
| [sherpa専用exporter](https://github.com/k2-fsa/sherpa-onnx/blob/master/scripts/sense-voice/export-onnx.py) | metadata、tokens、量子化。master参照のため再実験時にrevisionを固定する |

## 3. 言語別の報告とアプリ事例

| 出典 | 確度と用途 |
|---|---|
| [FunASR Discussion #1735](https://github.com/modelscope/FunASR/discussions/1735) | 日本語指定に関する公式回答。momeoでの比較結果ではない |
| [SenseVoice #130](https://github.com/QwenAudio/SenseVoice/issues/130) | 中国語→日本語の利用者報告。原因確定として引用しない |
| [SenseVoice #169](https://github.com/QwenAudio/SenseVoice/issues/169) | 指定言語と出力の相違の利用者報告 |
| [FunASR #2417](https://github.com/modelscope/FunASR/issues/2417) | 反復した数字のITNに関する利用者報告。Closed状態は修正の証明ではない |
| [AviUtl2-WhisperAutoSub](https://github.com/nkopikaso/AviUtl2-WhisperAutoSub/blob/main/README.md) | 日本語空白の処理を含む開発者記録。複数ASRのアプリ |
| [funasr-subtitle](https://github.com/rockbenben/funasr-subtitle) | 英語字幕の分割設計。アプリ作者の判断 |
| [Realtime Translator](https://github.com/baijunjie/realtime-translator) | 同系統のモバイル・browser利用と途中/確定表示 |
| [Obsidian realtime transcription](https://github.com/garetneda-gif/obsidian-realtime-transcription) | 認識後の用語補正とnative hotwordの区別 |
| [streaming-sensevoice](https://github.com/pengzhendong/streaming-sensevoice) | 第三者によるストリーミング・decoder拡張 |
| [SenseVoice CTC hotword fork](https://github.com/wsweishu/sherpa-onnx-sensevoice-hotword/blob/main/README_SENSEVOICE_CTC_HOTWORD.zh-CN.md) | 個人の拡張実装。標準sherpaの対応機能ではない |

## 4. 後処理・学習・export

| 出典 | 本調査で確認したこと |
|---|---|
| [FunASR後処理](https://github.com/modelscope/FunASR/blob/main/funasr/utils/postprocess_utils.py) | rich postprocessの役割。日本語空白除去の保証とはしない |
| [SenseVoice dataset](https://github.com/modelscope/FunASR/blob/main/funasr/datasets/sense_voice_datasets/datasets.py) | ラベルの既定値とデータ形式 |
| [finetune.sh](https://github.com/QwenAudio/SenseVoice/blob/ea15219509625e5d4c5143c37c86970135886b5d/finetune.sh) | 公式学習例。個人の少量日本語向け最適値ではない |
| [export.py](https://github.com/QwenAudio/SenseVoice/blob/ea15219509625e5d4c5143c37c86970135886b5d/export.py) | 古いONNXを再利用しないための確認点 |
| [長音声処理例](https://github.com/QwenAudio/SenseVoice/blob/ea15219509625e5d4c5143c37c86970135886b5d/long_audio_no_vad.py) | 有界長の窓・重複・生出力保持の参考 |

## 5. momeoの既存記録

- [採用判断](../decision/adopt-sensevoice.md): 体感と採用条件。条件の異なるRAM値を混同しない。
- [実装の段取りと完了追記](../decision/next-steps.md): 前半には実装前の文章も残る。現在値はコードを優先。
- [S6 SenseVoice](../spike/sensevoice.md): auto/ja、日本語中の英語、数字・空白の具体例。
- [S5 segmentation](../spike/segmentation.md): VADの実装仕様と、二重VADによる評価の歪み。
- [capture audit](../spike/capture-audit.md): 語頭の切り出しと連続音による確認。
- [baseline](../spike/current-baseline.md): 固定音声と録音時出力の比較条件。
- [辞書の検討](../spike/notation-dict.md): 見送った理由と適用限界。

## 調査の限界

日・英・中の一次資料を探しましたが、日本語の不要空白を直接解消するSenseVoice公式修正、日本語固有名詞に保証された設定、日本語の少量fine-tuningの確立したレシピは確認できませんでした。外部アプリの実装例を「momeoでも効く」という実証には使っていません。今回の成果は、設定の適用範囲と検証候補の整理です。
