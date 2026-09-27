# 機能とソースコード

調査対象: sherpa-onnx `v1.13.8`、ローカル `sherpa_onnx 1.13.8`。

## 役割を分けて考える

| 機能 | 答える問い | この用途での限界 |
|---|---|---|
| VAD | 音声らしい区間か | 誰の声か、本人か、テレビかはわからない |
| Speaker embedding | この区間の話者の特徴は何か | ベクトルを返す。単独で本人の名前や雑音ラベルは返さない |
| Speaker verification | 登録した本人の特徴と似ているか | 誤受理・誤拒否がある。スコアは本人確率ではない |
| Speaker identification | 登録者の誰に最も似ているか | 未登録者を既存の誰かに強制割り当てしないしきい値が必要 |
| Speaker diarization | 誰がいつ話したか | 匿名の話者番号を返す。別録音の同じ番号が同じ人とは限らない |
| ASR | 何と言ったか | 話者照合とは別のモデル・処理 |

根拠: [話者識別](https://k2-fsa.github.io/sherpa/onnx/speaker-identification/index.html)、[話者ダイアライゼーション](https://k2-fsa.github.io/sherpa/onnx/speaker-diarization/index.html)、[Silero VAD](https://github.com/snakers4/silero-vad)。

本人の特徴と似ていない理由には「別の人」だけでなく、短すぎる、雑音が多い、二人が重なる、登録時とマイク条件が異なる、といった可能性がある。これは各部品の出力から導かれる設計上の注意である。

## Dartで利用できるもの

ローカルの `~/.pub-cache/hosted/pub.dev/sherpa_onnx-1.13.8/lib/src/` と、[公式Dart登録・照合例](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/dart-api-examples/speaker-identification/bin/speaker_id.dart)を確認した。

| クラス | 確認したAPI |
|---|---|
| `SpeakerEmbeddingExtractor` | `createStream()`、`isReady()`、`compute()` → `Float32List`、`dim`、`free()` |
| `SpeakerEmbeddingManager` | `add()`、`addMulti()`、`contains()`、`remove()`、`search()`、`verify()`、登録名一覧、`free()` |
| `OfflineSpeakerDiarization` | 波形全体を受ける`process()`、進捗コールバック付き処理 |
| `OfflineSpeakerDiarizationSegment` | `start`、`end`、`speaker`、`confidence` |

入力は既存の音声ストリームと同じように、波形とサンプルレートを `acceptWaveform()` に渡す。WAVファイルへの書き出しは必須ではない。モデルを初期化して使い回し、発話ごとにストリームを作って解放できる。

### API名から誤解しやすい点

1. **`OnlineStream`は「本人判定が毎フレーム自動的に出る」という意味ではない。** General/NeMo実装の `compute()` は未処理フレームをまとめて処理し、処理済み位置を進める。移動窓や窓の重なりは呼び出し側で管理する。
2. **`isReady()`は品質判定ではない。** この版の実装は未処理の特徴フレームが存在するかを確認する。十分な発話長・単独話者・高いS/N比・識別精度は保証しない。
3. **特徴量はモデル依存。** `dim`を取得し、固定の次元数を仮定しない。モデルを変更したとき、以前の特徴量と新しい特徴量が同じ空間にあるとは限らない。

根拠: [General実装](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/speaker-embedding-extractor-general-impl.h)、[NeMo実装](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/speaker-embedding-extractor-nemo-impl.h)。

なお、ローカル版の[設定クラスの説明コメント](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/flutter/sherpa_onnx/lib/src/speaker_identification_config.dart)には `while (extractor.isReady(stream)) {}` という例がある。このままではready時に状態を進めず回り続けるため、コピーしない。実際の登録例のように音声を渡し、`inputFinished()`、必要な確認、`compute()`の順に処理する。公式コメントも実装と照合する必要がある。

## 登録・照合の中身

[speaker-embedding-manager.cc](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/speaker-embedding-manager.cc)を確認した結果:

- 一つの登録名につき、内部には一つの代表ベクトルを保持する。
- `add()`はL2正規化して登録する。同名がすでにあると失敗し、自動追記しない。
- `addMulti()`は入力ベクトルを合計し、その結果を正規化する。全サンプルを個別に保持して最近傍検索する機能ではない。各入力を先に正規化する処理もこの箇所にはない。
- `search()`は正規化した照合音声と登録ベクトルの内積を比較し、しきい値以上の最大候補を返す。
- `verify()`は指定された名前との同じ比較を行う。
- 永続保存・品質選別・経時的な更新・学習の処理はこのManagerにはない。

正規化後の内積はコサイン類似度である。例えば `0.8` は「本人である確率80%」ではない。しきい値の上下で誤受理と誤拒否の割合が変わる。

### スコアをアプリで扱う方法

この版のC++には `Score()` と `GetBestMatches()`、C APIにはスコア付き候補を返す `GetBestMatches()` がある。一方、確認したDartの公開 `SpeakerEmbeddingManager` には、それらのラッパーがない。`search()`は名前、`verify()`は真偽を返す。

momeoでは抽出した `Float32List` と自分で保存する基準ベクトルから、Dartで `dot(a,b)/(norm(a)*norm(b))` を計算する方法が取れる。少数の基準との比較ならネイティブAPIの拡張を必須にしなくてよい。ゼロノルム、非有限値、次元不一致は先に除外する。複数の基準を別々に持つ設計では、集約方法もしきい値とともに検証する。

根拠: [Dartラッパー](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/flutter/sherpa_onnx/lib/src/speaker_identification.dart)、[C API](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/c-api/c-api.h)。

## ダイアライゼーションの中身

`OfflineSpeakerDiarization` は、話者区間推定モデル・特徴抽出モデル・クラスタリングを組み合わせる。VADと本人照合だけの構成より処理が増える。

確認した `OfflineSpeakerDiarizationPyannoteImpl` では、特徴量抽出時に重複話者フレームを除外し、クラスタリング後に時間区間を構成する。**重複音声を波形として一人ずつ分離して出す処理ではない。** Dartの結果も区間と話者番号等であり、本人の登録名や話者ごとの波形、特徴量そのものは返さない。

根拠: [処理本体](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/offline-speaker-diarization-pyannote-impl.h)、[Dart結果の定義](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/flutter/sherpa_onnx/lib/src/offline_speaker_diarization_config.dart)。

### 同じthreshold/confidenceという名前でも意味が違う

| 値 | 実装での意味 | momeoでの扱い |
|---|---|---|
| Managerのthreshold | コサイン類似度の下限 | 大きくすると一致条件が厳しくなる |
| クラスタリングのthreshold | コサイン距離に基づく階層クラスタリングの切断値 | Managerの値を流用しない。大きくすると一般にまとめやすくなる |
| diarizationのconfidence | シルエット係数を基に区間に集約した値 | 本人確率でも、登録者への類似度でもない |

`numClusters > 0` ならクラスタリングのthresholdは使われない。本人／他人の二分類が欲しいから `numClusters=2` にするのも適切とは限らない。「他人」には複数の異なる話者が含まれるからである。

`computeConfidence` は既定で無効。未計算などのときは `-2` を返す。値の範囲だけを見て確率としてUIに表示しない。

根拠: [fast-clustering.cc](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/fast-clustering.cc)、上記処理本体・Dart設定。

## 既製品としては含まれていない部分

確認した版の公開APIとサンプルでは、次の機能を一体化した「本人だけを聞き取るモード」は見つからなかった。

- 初回登録UI、録音品質を見て登録を完了させるロジック。
- 本人・非本人・雑音・混在・不確実の包括的な判定。
- 常時入力に対する継続的な話者追跡と、別セッション間でのID維持。
- 本人特徴の安全な自動更新、最多発話者の集計、永続保存。

公式の [dynamicサンプル](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/python-api-examples/speaker-identification-with-vad-dynamic.py) は、既存話者に一致しなければ新しい匿名話者を登録する。登録済みベクトルの継続更新や「誰が所有者か」の推定は行わない。

## 実行環境

CPUで実行できる。`provider`には他の実行基盤もあるが、端末・ビルド・モデルの対応に依存する。[session.cc](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/session.cc)にはCoreML・NNAPI・XNNPACKなどの分岐とCPUへのフォールバックがある。

「CoreMLと設定すれば必ずNeural Engineで速くなる」「ダイアライゼーションは常にGPUを使えない」のどちらも、この調査では一般則として採用しない。まず現在の配布ライブラリでCPUを基準測定し、必要な場合に実行プロバイダーのログと実機性能を確認する。
