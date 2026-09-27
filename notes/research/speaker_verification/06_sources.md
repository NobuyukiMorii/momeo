# 調査ソース索引

調査日: 2026-09-27。基本実装は `v1.13.8` / `11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf`。各資料には結論の近くにもリンクを置いた。

## 公式ドキュメント・サンプル

| ソース | 確認したこと |
|---|---|
| [Speaker Identification](https://k2-fsa.github.io/sherpa/onnx/speaker-identification/index.html) | 機能の入口、配布モデルとサンプルへの案内 |
| [Speaker Diarization](https://k2-fsa.github.io/sherpa/onnx/speaker-diarization/index.html) | 区間推定と特徴抽出の二種類のモデル、各言語API |
| [Pre-trained diarization models](https://k2-fsa.github.io/sherpa/onnx/speaker-diarization/models.html) | Pyannote/Reverbと埋め込みモデルの組合せ、実行ログ |
| [Speaker recognition models](https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-recongition-models) | 配布ファイル、WAV、モデル固有のライセンスについての注記 |
| [同ReleaseのAPI](https://api.github.com/repos/k2-fsa/sherpa-onnx/releases/tags/speaker-recongition-models) | モデルの正確なバイト数 |
| [Dart登録・照合例](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/dart-api-examples/speaker-identification/bin/speaker_id.dart) | 複数の登録録音、照合、未知話者、リソース解放 |
| [VAD付きPython例](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/python-api-examples/speaker-identification-with-vad.py) | 発話ごとの抽出、平均登録、短区間のスキップ |
| [動的登録Python例](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/python-api-examples/speaker-identification-with-vad-dynamic.py) | 未知話者を匿名の名前で追加する動作 |
| [VAD＋識別＋ASR例](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/python-api-examples/speaker-identification-with-vad-non-streaming-asr.py) | 現在の版にSenseVoice分岐があること |
| [Dart diarization例](https://k2-fsa.github.io/sherpa/onnx/speaker-diarization/dart.html) | Dartでの利用経路 |

## 読んだ上流ソース

| ソース | 着眼点 |
|---|---|
| [speaker-embedding-extractor-impl.cc](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/speaker-embedding-extractor-impl.cc) | frameworkメタデータと対応モデル系列 |
| [General extractor](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/speaker-embedding-extractor-general-impl.h) | isReady、未処理フレーム、特徴量の前処理 |
| [NeMo extractor](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/speaker-embedding-extractor-nemo-impl.h) | 同上、モデル固有の前処理 |
| [Embedding manager](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/speaker-embedding-manager.cc) | 正規化、複数登録の集約、照合、更新の有無 |
| [C API](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/c-api/c-api.h) | スコア付き候補と結果のメモリ管理 |
| [Dart identification](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/flutter/sherpa_onnx/lib/src/speaker_identification.dart) | 現在のDart公開API。ローカルパッケージも確認 |
| [Dart diarization](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/flutter/sherpa_onnx/lib/src/offline_speaker_diarization.dart) | 波形全体の処理と結果の返却 |
| [Dart diarization config](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/flutter/sherpa_onnx/lib/src/offline_speaker_diarization_config.dart) | 既定値、confidence、セグメント構造 |
| [Diarization本体](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/offline-speaker-diarization-pyannote-impl.h) | 重複フレームの扱い、特徴抽出、結果の組立て |
| [Fast clustering](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/fast-clustering.cc) | 距離と類似度の違い、階層クラスタリング、シルエット係数 |
| [Session](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/session.cc) | 実行プロバイダーとフォールバック |

## モデル元・研究

- [3D-Speaker](https://github.com/modelscope/3D-Speaker): モデル系列と学習データ、ERes2NetV2の背景。
- [WeSpeaker](https://github.com/wenet-e2e/wespeaker): 話者認識のモデル・ツールキット。
- [TitaNet-largeモデルカード](https://huggingface.co/nvidia/speakerverification_en_titanet_large): 学習データ、評価条件、制約、CC-BY-4.0の記載。
- [Silero VAD](https://github.com/snakers4/silero-vad): 発話区間検出の役割。
- [ERes2NetV2論文、2024](https://arxiv.org/abs/2406.02167): 短時間話者照合を扱うモデル研究。要旨を確認。
- [SdSV Challenge評価計画](https://arxiv.org/abs/1912.06311): 短時間・発話内容・言語条件。要旨を確認。
- [NIST SRE21報告、2022](https://arxiv.org/abs/2204.10242): 言語・録音ドメインをまたぐ評価。要旨を確認。
- [Barrasら、Odyssey 2004](https://www.isca-archive.org/odyssey_2004/barras04_odyssey.html): 教師なし更新の実験。掲載要旨を確認。現在のニューラルモデルの性能保証には使わない。
- [Idiap、増分登録研究、2000](https://publications.idiap.ch/publications/show/792): 誤った話者の混入を含む増分登録の研究。検索に表示された要旨を確認。
- [NVIDIAの登録手順解説](https://perspectives.nvidia.com/nemotron-speech/task/faq/what-is-speaker-verification-and-how-do-i-build-a-voice-biometric-authentication/): 前の会話で参照した録音量の目安。sherpa-onnx共通要件ではない。
- [Personal VAD 2.0、2022](https://arxiv.org/abs/2204.03793): 本人の発話活動を逐次検出する関連研究。要旨を確認。sherpa-onnxでの対応モデルは未確認。
- [PVADの実環境評価、2024](https://arxiv.org/abs/2406.09443): 遅延、フレーム・発話・利用者単位の評価。要旨を確認。

## 利用者の一次報告・公開実装

本文とコメントをGitHub APIでも確認したIssue: [#769](https://github.com/k2-fsa/sherpa-onnx/issues/769)、[#1708](https://github.com/k2-fsa/sherpa-onnx/issues/1708)、[#2481](https://github.com/k2-fsa/sherpa-onnx/issues/2481)、[#2602](https://github.com/k2-fsa/sherpa-onnx/issues/2602)、[#1883](https://github.com/k2-fsa/sherpa-onnx/issues/1883)、[#2212](https://github.com/k2-fsa/sherpa-onnx/issues/2212)。関連の[PR #2492](https://github.com/k2-fsa/sherpa-onnx/pull/2492)は説明・コメントを確認。

[Discussion #3233](https://github.com/k2-fsa/sherpa-onnx/discussions/3233)は投稿者の構成・測定報告とBot返信を確認し、Botの断定を区別した。

[sherpa-diarize](https://github.com/qqlzfmn/sherpa-diarize)はREADMEと実装二ファイルを確認。コード参照はcommit `e7aae9c5d88511b5fea8a5b48aa418bf626a36b2` に固定。

Redditの [Swift報告](https://www.reddit.com/r/swift/comments/1lr3vn8)・[Flutter報告](https://www.reddit.com/r/flutterhelp/comments/1kzhu3t)は検索表示までの確認。本文の再取得はできず、低い確度の補助材料としてのみ記載した。

## ローカルの調査範囲

アプリの録音・モデル準備・初回遷移・保存処理を確認した。主な対象は `lib/stt/`、`lib/providers/stt_providers.dart`、`lib/providers/listening_providers.dart`、`lib/main.dart`、`lib/database/app_database.dart`、`lib/repositories/`、`pubspec.yaml`、`pubspec.lock`、`ios/Podfile.lock`。

調査用に公開ソースを一時ディレクトリへ取得したが、アプリの依存追加・コード変更・モデル更新はしていない。公開モデルのサイズはAPIのメタデータから、登録WAVの長さはファイルを取得してヘッダーから確認した。本人の音声を外部へ送る操作はない。
