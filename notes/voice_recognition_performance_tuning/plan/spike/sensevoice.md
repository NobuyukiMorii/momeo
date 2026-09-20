# S6 `sensevoice` — SenseVoice Small に差し替えて比べる

## 1. このセッションへの指示

- このセッションでやるのは **S6 だけ**。他のモデル（Qwen3・Nemotron）には進まない。
- 変えるのは**認識モデルだけ**。ライブラリは 1.13.8 のまま、区切り設定は S5 で決まった値のままにする。
- **配布の作り込みをしない。** Play Asset Delivery も準備ゲートも触らない。**モデルを端末に手で置いて、固定パスで読むだけ**でよい。
- S3 の音声と、S4 の記録が**必須**。無ければ**進まずに止まる**。
- 「軽い」「多言語」だけを理由に良い結果と書かない。**最優先は日本語**である。
- 結果は `notes/voice_recognition_performance_tuning/spike/sensevoice.md` に書く。**`main` にはマージしない。**

## 2. 背景

### 仮説

日本語・英語・中国語を1モデルで扱え（課題②③）、**日本語も現行に並ぶ**（課題①）。

**この仮説は棄却されうる。** 開発元の論文では SenseVoice-Small の日本語は 11.96 で、Whisper-large-v3（10.34）より悪いと公表されている。sherpa で配布されているのは Small のみで、良い Large は無い（`research/opus_repropose_v3.md` §1-C-2）。テストセットが違うので現行と直接は比べられないが、**日本語で現行に並ぶ根拠は無い状態で試す**。

### 答える問い

- 日本語は現行と比べてどうか
- 日本語に混ざる英語は、実際にどう出るか
- 英語・普通話は実用になるか
- 常駐RAM・異常終了・処理時間はどうか

## 3. 開始条件と依存

- ブランチ: `main` から `spike/voice_recognition_performance_tuning/sensevoice` を切り、**`sherpa_onnx` を 1.13.8** にする
- **依存**
  - `spike/current-baseline.md` と `.dev_models/spike_audio/` の音声（比較の基準）
  - `spike/lib-update.md`（土台の版を揃えるため）
  - S5 を実施済みなら、そこで決まった区切り設定に合わせる
  - **欠けていたら、このセッションはここで止める**
- **S1 `power-triage` の結果を先に読むこと。** ASR が電力の主因だったなら、この spike の重要度が上がる（軽い候補だから）

## 4. 作業の分担

| 誰が | 何を |
|---|---|
| エージェント | ブランチ作成、認識器の設定の差し替え、固定音声での実行、現行との突き合わせ、記録の下書き |
| **人** | **モデルのダウンロード（容量が大きい）と端末への配置の承認・実行**、実機への再インストール、出力の読み比べ |
| 止まる条件 | モデルの取得と端末への配置。容量と時間が大きいので人に頼む |

## 5. エージェントが行う手順

1. ブランチを切り、`sherpa_onnx` を 1.13.8 にする。
2. S3・S4 の記録と音声があることを確認する。**無ければ止める。**
3. S3 で作った「固定 wav を流す dev 経路」を用意する。
4. **モデルの取得手順を用意する**（実行は人）。対象は sherpa-onnx が配布する `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17`。
   - **2024-07 版を使う。** 2025-09 版は句読点に対応しないため、この spike では使わない
   - 中身は単一の `model.int8.onnx` と `tokens.txt`
   - 置き場所は、現行モデルの開発機手置きと同じ流儀にする。`lib/stt/stt_model_provisioner.dart` が使っている `getApplicationSupportDirectory()` の配下に、**spike 用のサブフォルダ**を作って置く（Android なら `run-as jp.momeo` の `files/` 配下。`scripts/place_android_device_models.sh` の `/data/local/tmp` 経由 → `run-as` コピーの流儀に合わせる）
   - **`SttModelProvisioner` 本体は変更しない。** spike の dev 経路の中で固定パスを直接読む
5. **認識器の設定を差し替える。** `lib/stt/stt_audio_worker.dart` の `_AudioEngine._createRecognizer` は現在 `OfflineModelConfig(nemoCtc: OfflineNemoEncDecCtcModelConfig(model: ...), tokens: ...)` を組んでいる。これを SenseVoice 用に置き換える。
   - 使う設定クラスは `OfflineSenseVoiceModelConfig`。フィールドは `model` / `language` / `useInverseTextNormalization`
   - `language` は空文字が自動判定。明示するなら `ja` / `en` / `zh` など
   - **句読点を出すには `useInverseTextNormalization` を有効にする**
   - **`language` を「自動」と「`ja` 固定」の両方で試す。** どちらが良いかは測って決める
   - 具体的なフィールド名と既定値は、着手時に `~/.pub-cache/hosted/pub.dev/sherpa_onnx-1.13.8/lib/src/offline_recognizer.dart` を開いて確認する。**想像で書かない**
6. **人に §6 を依頼する。ここで止まる。**
7. モデルが端末に置かれたら、S3 と同じ音声を同じ経路で流す。区分（日本語のみ / 日英混在 / 英語 / 普通話 / 雑音）ごとに出力をファイルへ書き出す。
8. 現行の出力（S3、S4 で更新があればその後の値）と**1件ずつ突き合わせる**。
9. 実行中の**常駐RAM の最大値・異常終了・1発話あたりの処理時間**も記録する。

## 6. 人が行う手順

1. モデルを取得する（圧縮で 150MB 前後、展開後 228MB 程度）
2. 端末へ置く（エージェントが手順を用意する）
3. 実機への再インストールの承認と操作
4. 出力を読み、次を返す

| 返してほしいもの | 形 |
|---|---|
| 日本語の読み返しやすさ | 現行と比べて良い / 同じ / 悪い。**実際の出力を引用して** |
| 英語混じりの見え方 | 英字で出たか、カタカナか、消えたか |
| 気になった誤り | 否定・数値・日時・人名の間違いは特に |

## 7. 観察・記録の枠

`notes/voice_recognition_performance_tuning/spike/sensevoice.md` に写す表。

### 言語ごとの結果（**平均して1つの順位にしない**）

| 区分 | 現行の出力 | SenseVoice の出力 | 人の判断 |
|---|---|---|---|
| 日本語のみ | | | |
| 日本語＋英語 | | | |
| 英語 | | | |
| 普通話 | | | |

### 動作

| 項目 | 現行 | SenseVoice |
|---|---|---|
| 1発話あたりの処理時間 | | |
| 常駐RAM の最大 | | |
| 異常終了 | | |
| 空の認識結果の件数 | | |
| 句読点 | | |

### 設定

| 項目 | 値 |
|---|---|
| モデル（版を明記） | sherpa-onnx-sense-voice-…-int8-2024-07-17 |
| `language` | 自動 / `ja` の両方の結果を書く |
| `useInverseTextNormalization` | |
| 区切り設定 | S5 で決めた値、または既定 |

## 8. やらないこと

- Play Asset Delivery、配布設計、準備ゲート、画面の作り込み
- `SttModelProvisioner` の本番の契約（ファイル名・期待バイト数・パス解決）の変更
- 他のモデルの評価（S7・S8 の担当）
- 用語登録（SenseVoice には sherpa の実装経路が無い）
- 区切り設定の追加の調整（S5 の担当）

## 9. 完了条件と、次へ渡すもの

**完了条件**: 日本語・日英混在・英語・普通話それぞれについて、現行と比べた結果が記録に残っていること。加えて RAM と処理時間が記録されていること。

**次へ渡すもの**: `spike/sensevoice.md` のみ。**コードはマージしない。**

- 日本語が現行に並んだ → 有力候補として残す。**ただし採用は全 spike のあと**
- 日本語が落ちた → 「軽さと多言語だけでは採らない」と記録し、**S7 `qwen3` へ進む**
