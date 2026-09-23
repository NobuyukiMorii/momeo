# SenseVoice の学習・モデル更新履歴と、今後の精度向上の見通し

調査日: **2026-09-23**。公式論文、開発元のリポジトリ・回答、Hugging Face / ModelScope の配布情報、sherpa-onnx の実装を確認した。momeo の参照コードは `982c3c6`。

ここでの「精度」は、音声を文字にする **音声認識（ASR）の精度**を指す。主な問いは「現在の仕組みを保ち、将来モデルを差し替えるだけで認識を良くできそうか」である。今回、新しい音声認識の実測やアプリの変更は行っていない。

「重み」は学習で決まった数値を保存したモデル本体、「checkpoint」はその保存版を指す。アプリの認識能力に直接関係するのは、この中身である。

## 1. 調査結果

**互換性のある改良モデルが出れば、今のアプリ構成を保って精度を上げることは可能。ただし、公式 SenseVoiceSmall が定期的に再学習され、日本語精度を改善した版が継続公開されているという実績は、今回の調査では確認できなかった。**

判断の根拠は次のとおり。

- **Alibaba のモデル、という理解は合っている。** 開発元は Alibaba Group の Tongyi SpeechTeam。個人プロジェクトではない。[公式プロジェクトページ][homepage]
- **公式標準の重みは、公開当初と同じだった。** Hugging Face の2024-07-04版と現在の `model.pt`、さらに現在の ModelScope 版で、公開メタデータの SHA256 とサイズが一致した。少なくともこの標準配布物には、約2年2か月分の再学習による更新は見られない。[重みの履歴][hf-weight-history]・[配布API][ms-files]
- **関連開発は続いている。** 2026年にも実行環境、量子化形式、連携機能などの更新がある。ただし、これを「日本語の聞き取り能力が上がった新版」とは数えられない。[リリース一覧][releases]
- **精度を改善した派生モデルと、別系列の新モデルは存在する。** 広東語向け追加学習版や Fun-ASR-Nano が該当する。改善する言語・構造・必要な実行環境が異なるため、SenseVoiceSmall の世代更新とは分けて考える。[広東語版][yue]・[Fun-ASR公式][fun-asr]

したがって、momeo では **「モデルを差し替えられる構成を維持する」価値はあるが、「待てば公式 Small の日本語精度が順次上がる」ことを開発計画の前提には置きにくい**。これは公開実績からの判断であり、開発終了を意味しない。

## 2. 誰が作り、どこで何を公開しているか

名前が似ているため、役割を分けて見ると更新を追いやすい。

| 名前・公開先 | 役割 |
|---|---|
| Alibaba / Tongyi SpeechTeam | SenseVoice を発表した研究開発チーム |
| SenseVoice / 現在の `QwenAudio/SenseVoice` | モデルの説明、推論・追加学習コード、関連リリース |
| `FunAudioLLM/SenseVoiceSmall`（Hugging Face） | 学習済み重みなどの配布 |
| `iic/SenseVoiceSmall`（ModelScope） | 同じ公式 Small の配布先 |
| `modelscope/FunASR` | 学習・推論・サービス提供などのツール群 |
| `k2-fsa/sherpa-onnx` | momeo が利用する推論環境と ONNX 変換・配布経路 |

開発元自身も、**モデルの重み・能力と、推論フレームワーク・サービスの更新は別の担当範囲**として整理している。`funasr` の版が上がっても、momeo に同梱した ONNX の学習内容が更新されるわけではない。[公式の役割整理][roles]

公式 Small は約2.34億パラメータで、普通話・広東語・英語・日本語・韓国語の5言語に対応する。論文の Large や研究全体に関する「50言語以上」の説明とは区別する。[公式 v1.0.0 のモデル仕様][v100]

## 3. どう学習しているのか

### 基礎モデルの学習

公式論文によると、**Small は5言語の約30万時間の音声で学習**している。Large はさらに約10万時間の多言語データを加える。「40万時間・50言語以上」をそのまま公開 Small の仕様とは扱わない。[論文 §3.1][paper]

Small は音声をまとめて処理する非自己回帰型のモデル。文字起こしには音声と文字列の対応を学ぶ CTC を使い、言語・感情・音イベントの分類も学習する。感情と音イベントの正解ラベルには、別の既存モデルが付けた疑似ラベルも使う。数字・句読点を整えた文と、整えない文を出す条件も学習する。[論文 §2.2・§3.1][paper]

### 公開後に追加学習する方法

公式は、利用者が音声と正解の文字起こしを用意して **fine-tuning（追加学習）**する経路を公開している。学習用・検証用データを作り、既存の `iic/SenseVoiceSmall` を出発点として別の重みを作る。言語・感情・イベントのラベルがない場合に、モデルで補う準備処理もある。[公式の追加学習手順][readme]

`finetune.sh` には途中の重みを保存し、検証し、良い checkpoint を保持・平均する設定がある。ただし、**この公開サンプルの学習回数などは、Alibaba が基礎モデルを実際に訓練した全条件や、今後の公開周期を示すものではない**。[追加学習スクリプト][finetune]

momeo は保存された重みを推論に使う構成なので、アプリを使い続けるだけで重みが学習・改善される仕組みではない。自分たちで改善するなら、正解付き音声の準備、追加学習、ONNX 変換、量子化後の確認、配布という別の作業が必要になる。

今回の公式資料では、基礎学習データ一式を再取得できる完全な一覧や、定期再学習・公開の運用計画までは確認できなかった。**「追加学習できる」と「開発元が継続して改良重みを公開する」は別の話**である。

## 4. 実際に、何がいつ更新されたのか

| 時期 | 確認できた出来事 | momeo の精度向上との関係 |
|---|---|---|
| 2024-07 | SenseVoice の論文・Small の公開。Hugging Face の `model.pt` は07-04に登録 | 現在の標準 Small の出発点。[履歴][hf-weight-history] |
| 2024-07-17 | sherpa 向け Small ONNX 配布物の日付 | momeo の現行モデル。これは変換・配布物の識別日であり、別の学習世代を意味しない。[sherpa一覧][sherpa-models] |
| 2025-09-09 | 広東語データで追加学習した派生モデルの sherpa 配布物 | 重みの異なる候補。ただし Alibaba による日本語の汎用改良版ではない。[sherpa一覧][sherpa-models] |
| 2025-12 | Fun-ASR-Nano-2512 系列を公開 | 開発元の別系列。Small v2 という位置づけではない。[Nanoモデルカード][nano-card] |
| 2025-12-17 | Nano 由来の CTC 部分を使う sherpa ONNX 配布物 | 同じ SenseVoice 経路で扱える候補がある。元の Nano 全体とは分けて評価する。詳しくは §6。[変換コード][nano-export] |
| 2026-05-25 | GitHub に `SenseVoice v1.0.0` を公開 | GitHub Release の日付。重みの2024年公開とは別で、このタグを新規再学習の証拠にはできない。[Release][v100]・[日時API][release-api] |
| 2026-06〜08 | llama.cpp / GGUF 実行環境の複数リリース。08-27に `runtime-llamacpp-v0.2.1` | CPU・GPU対応や配布バイナリなどの改善。Small の日本語精度向上版という発表ではない。[リリース一覧][releases] |
| 2026-09-23 確認時点 | 公式標準 `model.pt` は初期公開版と同じ識別子 | 公式 Small の新旧重みを並べた、日本語精度向上の時系列は作れない。下記の照合結果を参照 |

### 重みが同じ、と判断した具体的な根拠

リポジトリの最終更新日だけでなく、**重みファイルそのものの履歴と識別子**を確認した。

| 対象 | 確認結果 |
|---|---|
| Hugging Face の `model.pt` 変更履歴 | 2024-07-04 の `upload model.pt`、commit `2b05887414d06ebf81c0256c82b295450dcfc765` の1件 |
| Hugging Face の現在のリポジトリ revision | `3847d57b6bdf2dd8875cb1508d2af43d80a16bf7`。2026-06-20の GGUF 実行環境の案内追加 |
| 初期 revision と現在の `model.pt` サイズ | どちらも `936,291,369 bytes` |
| 初期・現在の Hugging Face LFS SHA256 | どちらも `833ca2dcfdf8ec91bd4f31cfac36d6124e0c459074d5e909aec9cabe6204a3ea` |
| 現在の ModelScope `iic/SenseVoiceSmall` の `model.pt` | 上記と同じ SHA256・サイズ |

確認元: [ファイル別履歴][hf-weight-history]、[全コミットAPI][hf-commits]、[初期版ファイル情報][hf-initial-tree]、[確認時の版のファイル情報][hf-current-tree]、[ModelScopeファイル情報][ms-files]。

これは配布サーバーが返すメタデータの照合であり、約936MBの重みをすべてダウンロードして手元で再計算した結果ではない。また、未公開の社内モデルや第三者の派生モデルまで「更新されていない」と主張するものでもない。

**最新の README、最新の GitHub Release、最新の ONNX 書庫の日付は、それぞれ「新しい学習済みモデル」の証拠にはならない。**

## 5. これまで、どのくらい性能が上がったのか

### 公式 Small の日本語精度は、年ごとの改善率を出せない

公式標準の重みが同じで、公式 Small の世代別比較も確認できないため、「毎年何％ずつ良くなった」という数字は出せない。同じ評価音声・同じ推論条件で、新旧の異なる重みを比較した資料が必要である。

初期論文の Common Voice 日本語 CER は Small **11.96%**、Large **9.19%**。これは2024年の異なるモデル構造・規模の比較で、Small の更新前後の成績ではない。CER は文字の誤り率で、小さいほど良い。[論文 Table 6][paper]

また、推論時間の短縮、量子化による省メモリ化、感情判定の改善は、それぞれ有用でも、日本語文字起こしの誤り率改善とは別の指標である。

### 追加学習による改善は、第三者の広東語版で確認できる

ASLP-lab の WenetSpeech-Yue は、SenseVoiceSmall を広東語向けに追加学習した重みを公開している。sherpa の2025-09-09版はこのモデルの変換で、説明では広東語 **21.8k時間**を使う。**句読点には対応しない**とも明記されている。[sherpaの配布説明][sherpa-models]

この派生研究では、まず中・高信頼度のデータを混ぜて学習し、その後に高信頼度のデータで追加学習する二段階の方法を採る。データを増やすだけでなく、正解ラベルの質を高めて仕上げる例である。[WenetSpeech-Yue 論文 §5.1][yue-paper]

開発者自身の広東語ベンチマークから、改善と悪化の両方が分かる例を抜粋する。指標は **MER（%）**で、中国語は文字単位、混在する英語は単語単位で誤りを数える。上記の日本語 CER と直接比較する値ではない。[同論文 Table 3][yue-paper]

| 広東語の評価セット | 元の Small の MER (%) | 追加学習版の MER (%) | 変化 |
|---|---:|---:|---|
| WSYue-eval / Short | 6.69 | 5.23 | 1.46ポイント改善、相対約22%減 |
| WSYue-eval / Long | 9.95 | 8.63 | 1.32ポイント改善、相対約13%減 |
| Common Voice / zh-HK | 7.34 | 8.68 | 1.34ポイント悪化 |

出典: [WenetSpeech-Yue の ASR Leaderboard][yue]。相対改善率は `(元の値 − 新しい値) / 元の値` で計算した。変換前モデルの公開評価であり、momeo の int8 ONNX や日本語音声で測定した値ではない。

この例は、**同じ規模のモデルでも追加学習で対象領域を改善できる一方、すべての条件で改善するわけではない**ことを示す。日本語の向上実績としては数えない。

## 6. 今後の開発方針を、どこまで読めるか

### SenseVoiceLarge の公開を予定に組み込めるか

開発側の LauraGPT は **2026-07-15**、公式 Large の重みは未公開で、提示できる公開予定日もないと回答している。論文上の Large の成績は、ダウンロード可能なモデルや公開期日の約束ではない。今回確認した公式モデル案内・Release にも Large はなかった。[開発側の回答][large-answer]

論文ではストリーミング対応を将来の研究方向に挙げるが、期限付きの公開計画ではない。[論文 §6][paper]

### 現在確認できる開発は、実行環境と別系列の ASR にも広がっている

公式の役割・ロードマップ資料には、サービス実装の整理、各実行経路の検証、コンテナ配布などが並ぶ。将来の版番号や日付は約束しないことも明記されている。**Small の日本語再学習版を定期公開する、という計画は今回確認した資料にはない。**[公式ロードマップ][roles]

一方、Fun-ASR-Nano / MLT-Nano という別系列を展開している。現在の公式案内では、Nano は中国語・英語・日本語と中国語の方言・アクセント、MLT-Nano は31言語を対象とする。両者や配布経路によって仕様が違うため、「Alibaba が新モデルを出した」だけでは、今の Small の差し替え可否や改善幅を判断できない。[Fun-ASR公式][fun-asr]

ここからの**推測**としては、今後の認識精度向上が Small の新版ではなく、別系列のモデルから提供される可能性も考えておくのが合理的である。ただし、開発元が Small の学習を終了した、あるいは Nano に全面移行すると宣言した、とまでは確認できない。

### momeo に近い候補として、Nano の CTC 派生版がある

`sherpa-onnx-sense-voice-funasr-nano-int8-2025-12-17` は、約264MBの ONNX と tokens を配布している。[配布ファイル][nano-onnx]

調べた sherpa-onnx **v1.13.8** のコードでは、この変換は `sense_voice_ctc` として登録される。モデル読み込み側にも Nano を区別する処理があり、**現在と同じ SenseVoice の設定入口を利用できる設計**である。この点では、アプリの大幅な作り直しなしで比較できる可能性がある。[変換処理][nano-export]・[モデル読み込み][sherpa-loader]

ただし、変換に用いるコードは CTC 付きの重みから **LLM と audio adaptor の部品を除く**。通常の Nano 全体と同じ推論ではない。SenseVoice の言語・感情・イベントタグを返す扱いでもない。[重みの読み込み処理][nano-core]・[認識結果の処理][sherpa-impl]

したがって、配布説明に転記された元モデルの「31言語」「認識精度93%」を、この CTC 版の日本語精度保証としては使えない。**小さな変更で試せそうな別候補ではあるが、公式 Small の確実な上位互換版とは未確認**、という位置づけになる。今回、モデル実体の実行・互換性試験は行っていない。

## 7. 「今の仕組みのままモデル交換」は、momeo で何を意味するか

現行 momeo は `sherpa_onnx: 1.13.8` を利用し、`OfflineSenseVoiceModelConfig` にモデルを渡している。重みと tokens の名前は `model.int8.onnx` / `tokens.txt`。現行の本体は `239,233,841 bytes` で、配布URL・書庫のSHA256・ファイルサイズを固定している。

確認元: [pubspec.yaml](/Users/mory/development/projects/mory/momeo/pubspec.yaml)、[認識器の生成](/Users/mory/development/projects/mory/momeo/lib/stt/stt_audio_worker.dart)、[取得元・配布定数](/Users/mory/development/projects/mory/momeo/scripts/lib/stt_model_constants.sh)、[端末側のサイズ確認](/Users/mory/development/projects/mory/momeo/lib/stt/stt_model_provisioner.dart)。

互換性のある新しい重みが得られた場合の作業は、おおむね次の順になる。

1. **重みと対応する tokens を一組で準備する。** PyTorch の `model.pt` を、そのまま現在の ONNX の代わりには置けない。
2. **現在の sherpa が読めることを確認する。** ONNX の入出力、metadata、語彙、言語・ITN の扱いなどが合う必要がある。
3. **配布物と固定値を更新する。** URL・書庫SHA256・サイズを変更する。サイズはスクリプトと Dart 側の両方にある。
4. **同じ録音で差を確認する。** 日本語、英語混じり、数字・固有名詞、欠落・繰り返しなどと、実機の時間・メモリを見る。モデル比較では音声区間もそろえる。
5. **現在の配布方式に載せてリリースする。** iOS はアプリ同梱、Android は asset pack 等の現行経路を使う。

つまり、録音・カード表示などを維持したまま改善できる余地はある。ただし、現状は公式モデルの最新版を自動取得する構成ではなく、**モデル差し替えを含むアプリ側の更新作業**になる。

| 今後出てきたもの | 現在の構成への近さ | 判断に必要なもの |
|---|---|---|
| Small と互換な日本語改良版・自前の追加学習版 | 高い可能性 | 対応ONNX、同一条件の精度比較、端末負荷 |
| 広東語向け追加学習版 | 読み込み形式は近い | 日本語精度と句読点・ITNの変化 |
| Nano の CTC 派生ONNX | 同じ認識入口を使える設計 | 実行確認、CTC版独自の精度・出力仕様 |
| Nano 全体、別構造の新モデル | モデルごとに異なる | 別の認識設定・対応ライブラリ・ファイル構成・負荷 |
| Small の GGUF / 新しい実行バイナリ | 現在の ONNX と形式が異なる | 実行環境の変更に見合う利点。再学習による向上とは別 |

## 8. 今後どの情報が出たら、期待値を変えてよいか

**見通しを変える強い証拠は、「新しい重み」「日本語の同条件比較」「momeo に載る配布形態」の3つがそろうこと。** 説明文の更新や GitHub の活動量だけでは足りない。

次に確認する場所は以下で十分である。これは確認先の提案であり、自動監視を設定したものではない。

| 確認先 | 注目する変化 |
|---|---|
| [公式 Small の重み履歴][hf-weight-history]・[ModelScope][ms-model] | `model.pt` の変更、別checkpointの追加、再学習の説明 |
| [SenseVoice Releases][releases]・[最新の公式README](https://github.com/QwenAudio/SenseVoice) | 日本語の評価結果を伴う新モデルの発表 |
| [Large に関する開発側回答][large-answer] | 公開先とモデルカードが実際に追加されたか |
| [Fun-ASR][fun-asr] | 別系列の小型モデル、オンデバイス向け候補 |
| [sherpa の配布一覧][sherpa-models] | 対応する ONNX・int8 版、語彙・出力仕様 |

現時点でのmomeo向け判断は、**現行 Small を使える品質として評価しつつ、互換モデルや軽い派生モデルが出たら同じ音声で試す**こと。将来の公式日本語改良版を、改善が約束された依存先として扱う根拠はまだない。

## 出典・照合範囲

以下は2026-09-23に確認。本文中の将来見通しは推測として記し、重みの同一性、公開日、実装上の対応とは分けた。`main` の資料は後日変わるため、重要なコード・文書は確認した版へ固定した。

- SenseVoice コード・README: `ea15219509625e5d4c5143c37c86970135886b5d`
- FunASR の役割・ロードマップ: `02f8b43fc9222e3d14d41565acbebbb23bf3b56c`
- WenetSpeech-Yue の公開比較表: `bea884c67f03f73f2d2d94557457a5849dd61090`
- sherpa の互換性確認: `v1.13.8`。momeo と同じライブラリ版のソースを参照
- GitHub Release の日付: 公開APIの `published_at`（UTC）を使用
- ModelScope のWebファイル一覧は取得できなかったため、公式公開APIのファイル情報で補った

[homepage]: https://fun-audio-llm.github.io/
[paper]: https://arxiv.org/html/2407.04051v2
[readme]: https://github.com/QwenAudio/SenseVoice/blob/ea15219509625e5d4c5143c37c86970135886b5d/README.md
[finetune]: https://github.com/QwenAudio/SenseVoice/blob/ea15219509625e5d4c5143c37c86970135886b5d/finetune.sh
[hf-weight-history]: https://huggingface.co/FunAudioLLM/SenseVoiceSmall/commits/main/model.pt
[hf-commits]: https://huggingface.co/api/models/FunAudioLLM/SenseVoiceSmall/commits/main
[hf-initial-tree]: https://huggingface.co/api/models/FunAudioLLM/SenseVoiceSmall/tree/2b05887414d06ebf81c0256c82b295450dcfc765
[hf-current-tree]: https://huggingface.co/api/models/FunAudioLLM/SenseVoiceSmall/tree/3847d57b6bdf2dd8875cb1508d2af43d80a16bf7
[ms-model]: https://modelscope.cn/models/iic/SenseVoiceSmall
[ms-files]: https://modelscope.cn/api/v1/models/iic/SenseVoiceSmall/repo/files?Revision=master&Recursive=true
[releases]: https://github.com/QwenAudio/SenseVoice/releases
[v100]: https://github.com/QwenAudio/SenseVoice/releases/tag/v1.0.0
[release-api]: https://api.github.com/repos/QwenAudio/SenseVoice/releases?per_page=100
[sherpa-models]: https://k2-fsa.github.io/sherpa/onnx/sense-voice/pretrained.html
[yue]: https://github.com/ASLP-lab/WenetSpeech-Yue/blob/bea884c67f03f73f2d2d94557457a5849dd61090/README.md#asr-leaderboard
[yue-paper]: https://arxiv.org/html/2509.03959v1
[large-answer]: https://github.com/modelscope/FunASR/discussions/1910
[roles]: https://github.com/modelscope/FunASR/blob/02f8b43fc9222e3d14d41565acbebbb23bf3b56c/docs/repository_roles.md
[fun-asr]: https://github.com/QwenAudio/Fun-ASR
[nano-card]: https://huggingface.co/FunAudioLLM/Fun-ASR-Nano-2512
[nano-onnx]: https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-funasr-nano-int8-2025-12-17/tree/f4bc255a2b45fa0b9bb0fbc53a20b94a16509c62
[nano-export]: https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/scripts/sense-voice/export_onnx_nano.py
[nano-core]: https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/scripts/sense-voice/rknn/test_nano_torch.py
[sherpa-loader]: https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/offline-sense-voice-model.cc
[sherpa-impl]: https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/offline-recognizer-sense-voice-impl.h
