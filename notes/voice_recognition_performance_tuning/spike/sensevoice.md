# S6 SenseVoice — 2026-09-21 実装・無音評価

## セッション引き継ぎ（作業中）

- ユーザーの制約: **周囲が寝ているため音を一切出さない。本人の発話も求めない。** 後続セッションでも録音・再生を勝手に始めない。
- 対象は **S6のみ**。S2・S3の聴感/正解確認、S5の設定探索、S7以降は未実施。
- 実験コード: `spike/voice_recognition_performance_tuning/sensevoice`。
- worktree: `/Users/mory/development/projects/mory/momeo/.dev_models/worktrees/sensevoice`。
- 実装コミット: `145046b`（計画取り込み: `ea24530`）。
- 枝元: S4 `8e75216`。sherpa_onnx **1.13.8**。計画はmainから取得。
- **この記録はmainが正本。実験コードをmainへマージしない。**

## 開始条件の確認

Android Pixel 8aが無線ADBで接続。端末の `files/spike_audio` に25 wav + answers.tsv + captured.tsv、S4のwhole結果を確認した。
基準は `whole_2026-09-20T23-55-35-905918.tsv`。録音時出力と比較しない。
S1結果を読み、軽い候補S6を先に実施。S5は未完了なのでVAD設定は変更しない。今回のモデル比較は丸ごと経路のみ。

## 実装

- `lib/main_spike_sensevoice.dart`: 通常のmain/ListeningPageを通らない入口。マイク・プレイヤー・録音サービスを起動しない。
- 既存 `SttFixedAudioSection` を再利用。NeMo / SenseVoice自動 / SenseVoice jaを画面で選択可能。全3条件×各2回の丸ごと実行も可能。
- `--dart-define=S6_AUTO_RUN=true` で起動後に同じ6回を自動実行。既存S3 wavをreadWave→transcribeWholeで直接処理し、音は出さない。
- SenseVoiceは固定パス `files/spike_models/sensevoice-2024-07-17/`。ITN有効、numThreads=1。SttModelProvisionerは変更しない。
- 切り替え時は前のworkerのisolate終了を待つ。認識器二重常駐によるRAM混入を避ける。
- 結果・状態は `files/spike_sensevoice/`。TSVにモデル・言語・版・ITN・スレッド数を記録。
- `scripts/setup_sensevoice.sh`: 公式アーカイブ取得、固定SHA256照合、必要2ファイルだけ展開、空き容量確認、既存の `/data/local/tmp`→run-as方式で配置、端末側SHA照合。
- `scripts/run_sensevoice.py`: 入れ替え前のAPK・評価音声・ラベル・設定・DBのバックアップ、S6 profile APKの上書きインストール、状態監視、約2秒間隔のdumpsys meminfo、結果回収、元APK復元。終了時はアプリを停止したままにする。

## 検証（作業中、実測結果は未確定）

- 変更3 Dartファイルのflutter analyze: 成功。
- Android arm64 profileビルド: 成功。
- setupスクリプトbash構文、runner Python構文/--help: 成功。
- 公式モデルアーカイブのSHA256確認・展開: 成功。端末配置/実測の結果は作業完了時に追記。

## モデル出典

公式説明: https://k2-fsa.github.io/sherpa/onnx/sense-voice/pretrained.html

- `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2`
- GitHub公式release APIでsize/digestを確認: 163002883 bytes、SHA256 `7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e`
- `model.int8.onnx`: 239233841 bytes、SHA256 `c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51`
- `tokens.txt`: 315894 bytes、SHA256 `f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc`

## 評価上の制限（引き継ぎ時に必読）

- 手元のanswers.tsvは24行、wavは25件。`2026-09-20T19-53-17-235773.wav` は未ラベル。
- 内訳はja=5、ja_en=4、en=2、zh=2、noise=11、すべてtuning。最終判定用は無い。
- 正解不明6行はen=2、zh=2、noise=2。「英語・普通話6件」という過去の記述は誤り。
- answerには認識結果のコピーがあり、確認済みフラグが無い。人が確認した正解と仮ラベルを区別できないので自動採点しない。
- S4の「正解確定3件」をそのまま信頼できる正解セットと見なさない。差分表はanswer_unverifiedとして扱う。
- 同じ固定wavの再実行はS3/S4で25/25一致。S6計画の「現行は同じ音声でも毎回変わる」は録音時との違いを混同した記述。S6では候補自身を2回回して確認する。
- 今回は固定wavを順次高速投入する評価。常時録音、リアルタイム待ち行列、画面OFF電池、長時間の熱を評価したことにはしない。
- 人の正解/読みやすさ確認は未完了。予備出力だけで採用を決めない。

## 実行上の問題（比較開始前）

最初のセッション `.dev_models/session_20260921_s6` は無線ADBのAPK転送が90秒でタイムアウトし、比較開始前に復元経路へ入った。モデルの失敗/性能結果には数えない。runnerをinstall/pullは300秒、installは `--no-streaming` に変更した。再実行は別ディレクトリに保存し、この失敗記録も残す。

## 再開手順

まずmainの本ファイルを読み、次にmainの `plan/spike/sensevoice.md` を読む。実験は上記worktreeで行う。別モデルへ進まない。

```bash
cd /Users/mory/development/projects/mory/momeo/.dev_models/worktrees/sensevoice
# 接続を確認。ここでは再生・録音をしない。
adb devices -l
# 未配置の場合のみ。既配置でもチェックサム検証して同じモデルを置く。
bash scripts/setup_sensevoice.sh
# 自動比較専用APK。通常のlib/main.dartを起動しない。
flutter build apk --profile --target-platform android-arm64 --no-pub \
  -t lib/main_spike_sensevoice.dart --dart-define=S6_AUTO_RUN=true
# --outは必ず未使用ディレクトリにする。--serialはその時点の接続ID。
python3 scripts/run_sensevoice.py --serial <adb-serial> \
  --apk build/app/outputs/flutter-apk/app-profile.apk \
  --out /Users/mory/development/projects/mory/momeo/.dev_models/<new-session>
python3 scripts/summarize_sensevoice.py \
  /Users/mory/development/projects/mory/momeo/.dev_models/<new-session> \
  /Users/mory/development/projects/mory/momeo/.dev_models/spike_audio/answers.tsv \
  /Users/mory/development/projects/mory/momeo/.dev_models/spike_results/whole_2026-09-20T23-55-35-905918.tsv
```

手動で画面の言語切り替えを試す場合は `--dart-define=S6_AUTO_RUN=true` を省いてビルドする。**通常入口で起動しない。** `flutter install` は使わず、データ保持の `adb install --no-streaming -r` を使用。現在のアプリへ戻す際は測定ディレクトリの `original.apk` を用いる。実験後に通常アプリを勝手に起動しない。

### 再開時に見る成果物

- `run.json`: 比較完了/失敗、元APK復元、評価データ不変の確認。
- `summary.json`: 条件別の2回の時間・空結果・サンプリングされた最大PSS/RSS。
- `review.tsv`: 差が出た音声のみ。人は `human_judgement` / `note` を編集する。`answer_unverified` を正解と断定しない。
- `*_repeat/summary.json`: 同一モデル2回の出力一致。
- `s4_vs_nemo/summary.json`: 今回のNeMoとS4の出力一致。
- `results/*.tsv`: 元の認識結果。端末の `files/spike_sensevoice/` にも残る。
- `memory.tsv` / `meminfo.txt` / `logcat.txt`: 測定生ログ。PSS/RSSはプロセス全体で、モデル単体の重みサイズではない。約2秒ごとの観測最大であり真のピーク保証は無い。
- `app-data-before.tar` / `original.apk`: 復旧用。音声・本番DBを含むためgitへ入れない。

同一プロセス内でNeMo→auto→jaの固定順で測る。前の認識器は解放するが、アロケータの保持領域や順序/温度の影響は排除していない。RAM/速度は予備評価として解釈する。

### 再試行で分かった実行条件の問題

`.dev_models/session_20260921_s6_retry` は起動に成功したが、端末がDozing、アプリがロック画面の背後で動き、NeMoの最初の30秒音声に約34秒かかる状態だった。画面点灯だけではNotificationShadeが前面のままで改善せず、比較条件が揃わないため途中で意図的にforce-stopした。この回の速度をモデル評価には使わない。

S6枝のAndroid MainActivityに、intent extra `spike_show_when_locked=true` の場合だけ `setShowWhenLocked` / `setTurnScreenOn` / `FLAG_KEEP_SCREEN_ON` を設定する実験オプションを追加。**keyguardを解除せず、録音サービスや音声再生を起動せず**、固定wav画面を前面に出す。通常起動はこのオプション無し。mainへは取り込まない。測定runnerがこのextraを渡して起動する。

## 2026-09-21 セッション終了の引き継ぎ

ユーザーがtoken残量のため区切りを依頼。追加の実装・別spikeには進まず、現在の比較・復元・記録で終了する。
正式な測定保存先は **`.dev_models/session_20260921_s6_foreground/`**。先の2ディレクトリは失敗/中断した予備試行なので混ぜない。
実行中にセッションが途切れた場合は、まず同ディレクトリの **`run.json`** を確認する。これが無ければrunnerがまだ測定/元APK復元中の可能性がある。**別のインストールや新しいrunnerを重ねて起動しない。** `status.json`、`restore.txt`、稼働中の `scripts/run_sensevoice.py` を確認する。`status.json` のcompleteだけでは元APK復元完了を意味しない。

再開担当の最初の作業は、run.jsonの `originalApkRestored` と `audioUnchanged` が両方trueか確認し、未集計なら上のsummarizeスクリプトを正式測定保存先に対して実行すること。その後、review.tsvをもとに人の判断を記録する。**音声再生・新規録音はこの依頼では許可されていない。**

---

## 集計結果（2026-09-21 早朝、音を出さずに実施）

`summarize_sensevoice.py` を正式測定 `.dev_models/session_20260921_s6_foreground/` に対して実行した。
録音・再生・端末操作はしていない。既存 TSV の突き合わせのみ。

### 測定が成立していることの確認

| 確認項目 | 結果 |
|---|---|
| `run.json` | `failure: null` / `audioUnchanged: true` / `originalApkRestored: true` |
| **S6 の NeMo と S4 の NeMo が一致するか** | **25/25 完全一致**（`s4_vs_nemo` の `changedRows` が 0） |
| NeMo を2回流したとき | 25/25 一致 |
| SenseVoice auto を2回流したとき | 25/25 一致 |
| SenseVoice ja を2回流したとき | 25/25 一致 |

**土台が S4 と同一であることが数字で取れている。** したがって以下の差は、実行ごとのゆらぎでも土台の違いでもなく、**モデルの違いに帰属する**。
**SenseVoice も決定的**である。S3・S4 の NeMo と同じく、同じ wav を流せば同じ出力が返る。

### 機械が測れた範囲

| | NeMo CTC 0.6B | SenseVoice auto | SenseVoice ja |
|---|---|---|---|
| 空の結果 | **1 件** | **0 件** | **0 件** |
| 異常終了・エラー | 0 | 0 | 0 |
| 観測された最大 PSS | **1,393 MB** | **778 MB** | **780 MB** |
| 観測された最大 RSS | 1,506 MB | 891 MB | 893 MB |
| 426.05 秒の認識にかかった時間 | 46.2 / 45.7 秒 | 30.9 / 37.5 秒 | 40.0 / 42.4 秒 |

**常駐 RAM が 44% 小さい。** これは S7 `qwen3` の RAM 懸念とも比較できる基準値になる。
**速度は断定しない。** SenseVoice auto は同一条件の2回で 21% 開いており（30.9 秒と 37.5 秒）、この幅の中では優劣を言えない。ただし**両モデルとも実時間の 7〜11% しか使っておらず、速度は採否を分ける軸ではない**。

### 出力の中身（**人の確認が要る。以下は判定ではなく観察**）

**1. 英語が出る。** S3・S4 で最大の壊れ方だった 34.65 秒の英語が、全文で出た。

| | 出力 |
|---|---|
| NeMo | `そうシ` |
| SenseVoice | `Also from now, I just start to speak in English. I'm a just Japanese English speaker. so maybe my pronunciation is not so correct...` |

**S4 で「原因はモデルか VAD の側にある」と絞り込んだ件は、モデル側だった。**

**2. `noise` と分類していた行の多くは、英語の発話だった。** NeMo が出せなかったために正解不明のまま `noise` に落ちていた。

| 音声 | NeMo | SenseVoice auto |
|---|---|---|
| 6.11 秒（S3・S4 で空だった行） | `でした` | `For example, if I speak like this in English suddenly, can you understand.` |
| 5.50 秒 | `オーnw` | `Oh, no way. I'm speaking in English. You have to listen to me.` |

**`answers.tsv` の区分そのものが、現行モデルの出力に引きずられている。** 区分の振り直しが要る。

**3. 普通話が漢字で出る。** `オシーリベレン、ウーダアイハウワイダタイ台ウ` → `我是日本人，我的爱好是网球...`。
**ただし言語を `ja` に固定すると普通話は崩れる**（`日本网球在中文日本太イ太太太国台湾台湾我脑习中文。`）。**`auto` を使う根拠になる。**

**4. NeMo が日本語の節を丸ごと落としていた可能性がある（要確認）。**

| | 出力 |
|---|---|
| NeMo | …日本史についてはよくわからないんだけれども**、例えば明治時代の**… |
| SenseVoice | …日本史についてはよくわからないんだけれども、**世界史についてはよく知っています** 例えば明治時代の… |

もう1件（`19-50-29`）でも SenseVoice だけが `表現方法が少し違いますと` を出している。
**`answers.tsv` の `answer` は NeMo の出力から作られているため、落ちた節は正解側にも入っていない。** 言ったかどうかは**本人しか判定できない**。

**5. 日英混在は、英語がカタカナになる。** `iphone` → `アイフォン`、`airdrop` → `エアジョロ`、`iicsinck` → `アイシンク`。
表記は**実行ごとには揺れない**（決定的）ので課題②の「表記が定まらない」は解消する方向だが、**ラテン文字表記そのものが失われる**。`ITリテラシー` は `アイティイテラス` に崩れている。**これを良しとするかは好みの問題で、機械では決められない。**

**6. 句読点と空白が付く。** ITN 有効のため `。` `、` が入る。一方で `それ に比較して、徳川 家康だっ たりとか。` のように**不自然な空白**も入る。

**7. 数字は直っていない。** `1600年` を NeMo は `162年`、SenseVoice は `16002年` と出す。**どちらも誤り。**

### 人に判断してもらう必要があるもの

`review.tsv`（25行、`human_judgement` は全行 `pending`）。**自動採点はしていない。** `answer_unverified` 列は確認済みの正解ではない（`answers.tsv` の 24 行中 17 行は認識結果のコピー）。

判定が要るのは次の3点である。

1. **落ちた節を本当に言ったか**（上記4。言ったなら、NeMo は日本語でも取りこぼしている）
2. **カタカナ表記を受け入れるか**（上記5。課題②の答えが変わる）
3. **英語・普通話の正解**（SenseVoice の出力が読めるので、**ゼロから書き起こす必要はなく、直すだけで済む**）

### この spike から後続への申し送り

- **S3 の残タスクのうち、英語・普通話の正解確定は難度が下がった。** 録り直さなくても、SenseVoice の出力を叩き台にできる。`最終判定用` の収録は依然として残る
- **`answers.tsv` の `category` を振り直す。** `noise` 11 件のうち複数は英語の発話である
- **RAM 778 MB を S7 `qwen3` の比較基準にする**
- **言語指定は `auto`。** `ja` 固定は普通話を壊し、日本語側の利得も無い（18/25 行で差が出るが、日本語行では改善していない）
- **採用は決めない。** 上の3点を人が判断するまで、SenseVoice は「有力候補」までである
