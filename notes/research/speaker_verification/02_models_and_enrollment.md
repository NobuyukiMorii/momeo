# モデルと初回登録

## 対応モデルと比較候補

`v1.13.8` の [モデル選択実装](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/speaker-embedding-extractor-impl.cc)はONNXの `framework` メタデータを見て、WeSpeaker・3D-Speaker・NeMoを選ぶ。任意のONNXファイルを置けば動くわけではない。最初はsherpa-onnx向けに配布されたモデルを使うのが検証しやすい。

下表は[公式配布](https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-recongition-models)のファイルサイズをGitHub APIで確認したもの。MBは10進、メモリ使用量ではない。モデル本体をダウンロードして推論比較した結果ではない。

| 配布ファイル | サイズ約MB | 比較に入れる理由／注意 |
|---|---:|---|
| `3dspeaker_speech_campplus_sv_zh-cn_16k-common.onnx` | 28.28 | 小さめの候補。日本語精度は未確認 |
| `3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx` | 28.28 | 別の学習条件の比較候補。名前だけで日本語対応を断定しない |
| `wespeaker_en_voxceleb_resnet34_LM.onnx` | 26.53 | WeSpeaker系列の比較候補 |
| `3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx` | 39.59 | 公式ダイアライゼーション例に登場する候補 |
| `nemo_en_titanet_small.onnx` | 40.26 | 公式の速度例に登場。ファイルが小さい順と速度順は一致しない |
| `3dspeaker_speech_eres2netv2_sv_zh-cn_16k-common.onnx` | 71.44 | 短い発話を重視したモデル系列として比較価値がある |
| `nemo_en_titanet_large.onnx` | 101.41 | 精度側の比較対象。常時モバイル利用では負荷も評価 |

最初の比較候補を少数にするならCAM++、TitaNet-small、ERes2NetV2など、サイズ・構造が異なるモデルを選ぶ案がある。これは選定案であり推奨モデルの確定ではない。

[ERes2NetV2論文](https://arxiv.org/abs/2406.02167)は短時間の話者照合を扱う。ただし論文の評価条件、配布重み、日本語のmomeo録音は同一ではない。モデル名やベンチマークだけで短い日本語の相づちを識別できるとは言えない。

## 日本語への適用

話者照合は発話テキストの一致を要求するものではないが、言語差や収録環境差がなくなるわけではない。今回確認した配布名は英語・中国語由来が中心で、momeo相当の日本語スマートフォン録音で比較した公式表は見つからなかった。

[TitaNet-largeのモデルカード](https://huggingface.co/nvidia/speakerverification_en_titanet_large)は英語データ中心の学習と、利用ドメインが異なる場合の注意を記載する。掲載のVoxCeleb1 EER 0.66%は、その評価条件での値であり、momeoの誤判定率には置き換えられない。[NIST SRE21の報告](https://arxiv.org/abs/2204.10242)でも、言語・録音ドメインをまたぐ評価を別の難しさとして扱っている。

## 初回登録に何秒必要か

**sherpa-onnx共通の「N秒なら十分」という保証は確認できなかった。** 抽出APIの受付条件、公式デモの録音量、製品の精度に必要な録音量を区別する。

公式配布WAVを取得し、Python標準 `wave` で `nframes / framerate` を計算した。すべて16kHz・1chだった。以下は無音を含むファイル長であり、VAD後の実発話長ではない。

| 登録例 | 各ファイルの秒数（小数3桁に丸め） | 合計約秒 |
|---|---|---:|
| fangjun | 2.299 / 5.166 / 2.821 | 10.286 |
| leijun | 4.201 / 4.760 | 8.961 |
| liudehua | 2.980 / 3.949 | 6.929 |

根拠: [配布WAV一覧](https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-recongition-models)、[複数録音を使うDart例](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/dart-api-examples/speaker-identification/bin/speaker_id.dart)。Dart例で登録するのは前二人で、三人目は未知話者として試す構成。

会話中に提案した「5〜10秒を3回、合計15〜30秒」は、余裕を持たせた初期実験案として残す。[NVIDIAの解説](https://perspectives.nvidia.com/nemotron-speech/task/faq/what-is-speaker-verification-and-how-do-i-build-a-voice-biometric-authentication/)にも各5秒以上を3〜5回という例はあるが、別製品の説明をsherpa-onnxの必須仕様にはしない。

### 読み上げUIの方向性（案）

- 短い文章を複数読む。毎回同じ合言葉しか判定できない方式にする必要はない。
- 録音の経過秒数ではなく、発話の長さ・音割れ・無音・特徴量間の整合性を見て、使えるサンプルが集まったか判定する。
- 特徴量が大きく外れる録音は、雑音・他人の混入・音声条件の違いを確認する候補にする。整合性だけで「本人である」と証明はできない。
- 登録用とは別の文章を最後に一度話し、その音声を照合確認に使う案がある。同じサンプルを登録と評価の両方に使うと評価が楽観的になる。
- 自然な話し方で登録できる文面を検討する。多数の文章を必須にする前に、合計10秒・20秒・30秒程度の条件で効果を比べる。

文章の数、秒数、再録条件はまだ決めない。発音・言い直しの正確さを主目的にせず、声の比較に使える録音を得ることが目的。

## 登録後の短い発話

初回登録が長くても、照合する「うん」「はい」が短ければ別の問題が残る。公式 [VAD付き識別例](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/python-api-examples/speaker-identification-with-vad.py)は0.5秒未満をスキップするが、0.5秒以上なら精度を保証する意味ではない。[短時間話者照合の評価計画](https://arxiv.org/abs/1912.06311)も、短時間・発話内容・言語の条件を分けて扱っている。

本人と判定した直前の話者を短い相づちに引き継ぐ方法は候補だが、話者交代時に他人の声を本人扱いする可能性がある。短い発話を自動更新の材料から外し、判定保留にできる構成から評価する。

## モデルサイズ、実行速度、保存量は別

公式の[ダイアライゼーション実行例](https://k2-fsa.github.io/sherpa/onnx/speaker-diarization/models.html)には、56.861秒の音声をTitaNet-small＋Pyannoteで6.756秒、RTF 0.119で処理したログがある。これは処理全体の特定条件の例で、本人照合単体の速度でもmomeo実機の測定でもない。`model.int8.onnx` が区間推定モデルを指す例では、特徴抽出モデルもint8になったと解釈しない。

保存する特徴量自体は小さい。例えばD次元のfloat32をK本なら数値部分は `4 × D × K` バイト。モデルファイルや推論時メモリとは別に考える。モデルID・版・正規化方法・登録情報も一緒に保存する必要がある。

モデルの利用条件は配布物ごとに確認する。[公式配布ページ](https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-recongition-models)も各モデル固有のライセンス確認を求めている。TitaNet-largeのモデルカードはCC-BY-4.0だが、これを他のモデルに一般化しない。今回、全候補の権利条件の確定までは行っていない。
