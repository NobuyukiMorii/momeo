# 利用者の経験と実装事例

報告の時期・使用言語・モデル・端末が違うため、現在のmomeoで再現するとは限らない。作者・利用者の一次報告と公開コードを優先し、Botの回答は独立した根拠にしない。

## 1. スコアを見てしきい値を調整したい

[Issue #769](https://github.com/k2-fsa/sherpa-onnx/issues/769)（2024-04-15）では、Pythonの話者識別が動いた利用者が、一致しない理由の調査としきい値調整のためにスコア出力を求めた。メンテナーは既存APIを壊さず新APIを追加する方向を案内している。

**momeoへの示唆:** 真偽だけでは比較実験がしにくい。本人・他人のスコア分布、発話長、録音条件を観察できる調査用表示が役立つ。現在のDartでは自前のコサイン類似度計算が候補になる。

## 2. Pyannote本家と結果が一致しない報告

[Issue #1708](https://github.com/k2-fsa/sherpa-onnx/issues/1708)（2025-01-14）では、Pyannoteでは二人に分かれた音声がsherpa-onnx側で一人として出たと報告された。モデルの選択、特徴量、前処理の確認が議論されている。読めたコメントでは原因と修正を確定できなかった。

途中で「コサイン類似度」とSciPyが返す「コサイン距離」の取り違えも議論された。`distance = 1 - similarity` の関係を確認している。2025年9月には重複発話の結果がよくないという別利用者の追記もある。

**momeoへの示唆:** 同じ系列のモデルを選んでも、全パイプラインが同じになるとは限らない。しきい値名だけで値をコピーしない。重複発話は独立した評価条件にする。

## 3. ダイアライゼーションの処理時間がASRより長い

[Discussion #3233](https://github.com/k2-fsa/sherpa-onnx/discussions/3233)（2026-02-27）の投稿者は、Linux・RTX 3090・Goで21.2分の音声にPyannote＋ERes2Net-base＋SenseVoiceを利用し、話者分けに約4分57秒、続くASRに約23秒と報告した。117話者と出たという記述もあり、設定や結果の品質にも疑問が残る。

これは一人の環境での報告であり、momeoの所要時間予測には使わない。返信のBotが断定する「CPUでしか動かない」という説明は、現在のソース確認によって一般則としては採用しない。

**momeoへの示唆:** ASRが軽快でも、話者分けを加えると負荷が増える。CPU/GPU指定の文字列だけで判断せず、実際の実行基盤・各処理時間を測る。

## 4. iOS/Swiftで特徴量を使いたい

[Issue #2481](https://github.com/k2-fsa/sherpa-onnx/issues/2481)（2025-08-10）に対し、メンテナーは[PR #2492](https://github.com/k2-fsa/sherpa-onnx/pull/2492)の特徴量抽出例を案内した。話者分けの時刻から元音声を切り出し、その音声の特徴量を抽出する方法である。

[Issue #2602](https://github.com/k2-fsa/sherpa-onnx/issues/2602)（2025-09-17）では、BotがSwift例はないと回答した直後に、メンテナーが既存の `compute-speaker-embeddings.swift` を案内している。

**momeoへの示唆:** 検索結果や自動回答だけでAPIの有無を判断しない。Dartを基本経路にできるため、今すぐSwift/Kotlin側に新しい実装を作る必要はない。

## 5. SenseVoiceとの組み合わせ

[Issue #1883](https://github.com/k2-fsa/sherpa-onnx/issues/1883)（2025-02-18）は、VAD＋話者識別＋非ストリーミングASR例でSenseVoiceが使えないという報告だった。しかし今回確認した `v1.13.8` の[同サンプル](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/python-api-examples/speaker-identification-with-vad-non-streaming-asr.py)には `from_sense_voice()` の分岐が存在する。

**momeoへの示唆:** 過去のサンプルの未対応を、現在のライブラリの原理的な制限と混同しない。現在のmomeoも、同じ発話音声をそれぞれのモデルに渡す構成を取れる。

## 6. 配列型の落とし穴

[Issue #2212](https://github.com/k2-fsa/sherpa-onnx/issues/2212)（2025-05-14）では、Pythonサンプルの配列がfloat64になる問題について、メンテナーがfloat32指定の必要性を認めている。

**momeoへの示唆:** Dartの `Float32List` を維持する。サンプルレート、チャンネル数、正規化範囲も、モデル比較の前提としてそろえる。

## 7. sherpa-onnx上にオンライン話者追跡を作った事例

[qqlzfmn/sherpa-diarize](https://github.com/qqlzfmn/sherpa-diarize)は、Silero VADと特徴抽出に、独自の話者追跡・長い区間の再分割を加えたPython実装。調査時のcommitは `e7aae9c5d88511b5fea8a5b48aa418bf626a36b2`。

READMEの説明に加え、次のソースを読んだ。

- [clustering.py](https://github.com/qqlzfmn/sherpa-diarize/blob/e7aae9c5d88511b5fea8a5b48aa418bf626a36b2/sherpa_diarize/clustering.py): L2正規化と類似度で話者を割り当て、代表ベクトルを指数移動平均で更新。定期的に近いクラスタを統合する。
- [pipeline.py](https://github.com/qqlzfmn/sherpa-diarize/blob/e7aae9c5d88511b5fea8a5b48aa418bf626a36b2/sherpa_diarize/pipeline.py): 長い区間の短い無音を候補にし、前後の特徴量を比較して話者交代を調べる。

コードでは更新係数の既定値が0.6で、新しい発話の影響が大きい。受理された発話で代表ベクトルを更新するが、初回に確認した「本人」を固定する仕組みはない。これをそのまま永続的な本人プロフィールに使うと、誤判定の影響を後続の判定へ持ち越す可能性がある、というのが今回のコードからの推論。

返す `confidence` は既存クラスタとの類似度で、新規クラスタでは近い既存クラスタとの類似度を使う。新規話者の正しさの確率ではない。

作者はデモ音声で4話者を区別できたと説明しているが、独立した検証はしていない。README上もAndroidネイティブへの移植は計画段階。**モバイルで出荷済みの精度・電池持ちの実績としては扱わない。**

## 8. モバイル利用者の補助的な報告

- [Swiftの開発者投稿](https://www.reddit.com/r/swift/comments/1lr3vn8): sherpa-onnxを動かせたが、話者分けと文字起こしを繰り返すと古い端末で遅くなった、という作者の経験。CoreMLで別実装した背景を説明している。
- [Flutterの利用者投稿](https://www.reddit.com/r/flutterhelp/comments/1kzhu3t): `flutter_wake_word` と `libonnxruntime.so` の重複で困ったという報告。

この二件は検索インデックスに表示された投稿内容まで確認し、本文の再取得はできなかった。構成・版・再現条件を完全には確認していないため、補助情報に留める。現在のmomeoには `flutter_wake_word` はなく、同じ衝突があると判断する根拠にはならない。

## 9. 自動更新の研究

[Barrasら、Odyssey 2004](https://www.isca-archive.org/odyssey_2004/barras04_odyssey.html)では、しきい値や重みを用いた教師なし更新で話者検証性能が改善した実験を報告している。ただし電話音声・GMMの研究であり、現在のニューラル特徴量とスマートフォンの常時録音に同じ数値を当てはめられない。

[Idiapの増分登録研究](https://publications.idiap.ch/publications/show/792)は、本人以外が混入する場合を含む更新の振る舞いを扱っている。

**momeoへの示唆:** 自動更新という方向には研究上の根拠があるが、常に改善する保証はない。固定した初回基準と更新後の基準を、同じ未使用の評価音声で比較する必要がある。
