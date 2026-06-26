# Step 8: Android fast-follow の本配信＋ネイティブブリッジ

## ひとことで言うと

Android で 625MB の NeMo を**本番でユーザーに届ける**ステップ。
Step 6 で作った「`adb push` 事前配置」を、本物の Play 配信（**fast-follow**）に置き換える。

iOS の NeMo は Step 6 のバンドルリソースで配信が完成しているので、**このステップは Android 専用**。
全ステップの中で最重・最もリスクが高い部分なので、core（Step 7 の文字化）が動いたあとに**独立させて隔離**してある。

> 配信モードを fast-follow にした理由（コピー不要・ディスク半減・実装軽量）と判断経緯は
> [model_distribution.md](model_distribution.md) と
> [../research/on_device_stt/model_delivery_decision_for_beginners.md](../research/on_device_stt/model_delivery_decision_for_beginners.md)、
> 実装手段（薄い自前ブリッジ）の調査は
> [../research/on_device_stt/model_delivery_flutter_impl.md](../research/on_device_stt/model_delivery_flutter_impl.md) を参照。

---

## このステップの目的

Step 6 で**パス契約**（`SttModelProvisioner`＝「実パスを返す」窓口）は出来ている。
下流（Step 7 の文字化・Step 9 のスプラッシュ・Step 10 の結線）は**実パスしか見ない**ので、
ここで Android の「実パスの出どころ」を **事前配置 → fast-follow** に差し替えるだけで、下流は影響を受けない。

```
[下流は変わらない]  認識器生成 / スプラッシュ / 結線
        ↑ 実パスだけ
   パス契約（SttModelProvisioner）
        ↑ ここの Android 実装だけを差し替える
   事前配置（Step 6）  →  fast-follow 実パス（このステップ）
```

fast-follow は「本体インストールには含めず、**インストール直後に Play が自動DL**する大容量パック」。
DL 完了後は `getPackLocation().assetsPath()` で**展開済みの実パス**が取れ、そのまま sherpa に渡せる（コピー不要）。

---

## やること

### 1. fast-follow アセットパックを用意する（Gradle 配線）

- `asset-delivery` 依存（`com.google.android.play:asset-delivery`）を追加する。
- fast-follow アセットパック用の**小モジュール**を定義し、`settings.gradle.kts` / `build.gradle.kts` に紐付ける（現状は `:app` のみ）。これは **Android 専用の配線**。
- 200MB 制限を超えるため普通のアセットには入れられないので PAD を使う。NeMo 625MB は**パック上限 1.5GB 内に収まる**（「512MB上限」は誤情報。[model_delivery_flutter_impl.md](../research/on_device_stt/model_delivery_flutter_impl.md) §2-1）。

### 2. `AssetPackManager` の薄いネイティブブリッジを実装する

- `getPackLocation(pack).assetsPath()` … 完了後の**実パス**を取る。
- `getPackStates()` / `registerListener(AssetPackStateUpdateListener)` … **状態・進捗・失敗**を取る。
- （必要なら）`fetch()` … 未DL時の保険・再試行に使う。
- Dart へは MethodChannel / EventChannel で「実パス」と「準備状態・進捗」を渡す。

> **既製の `asset_delivery` パッケージは使わない。** あれは **on-demand 専用**で fast-follow（`getPackLocation`・状態リスナー）をラップしておらず、コア経路に乗せると壊れたとき直せない。必要な Android API はごく少数なので、**薄い自前ブリッジ**で確実に自分の制御下に置く。比較は [model_delivery_flutter_impl.md](../research/on_device_stt/model_delivery_flutter_impl.md) を参照。

### 3. パス契約の Android 実装を差し替える

- Step 6 の「事前配置先の実パスを返す」を、**fast-follow 完了後の `getPackLocation` 実パスを返す**に差し替える。
- 開発の利便のため、**事前配置（`adb push`）と fast-follow の両対応**にしておく（dev は事前配置、本番は fast-follow）。
- パス契約の窓口の内側だけが変わり、下流（Step 7/9/10）は無影響。

### 4. 初回DL未到着の「準備状態」を公開する

fast-follow では、**インストール直後はまだDL中でモデルが無い**状態が起こり得る。これは Step 6 の事前配置には無かった新しい状態。

- provisioner に **準備状態（未開始／DL中／完了／失敗）・進捗・`ensureReady()`・再試行** を公開する。
- momeo には Intro 1〜4 ＋ Setting のオンボーディングがあるので、**その間に背景DLが進む**想定。多くの場合、最初の音声メモ画面に着くころには完了している。
- この準備状態を**消費する側**は別ステップ：スプラッシュの「準備中」表示は **Step 9**、音声入力を始めさせない**ガード**は **Step 10**。本ステップは「状態を正しく公開する」ところまで。

### 5. dev catalog に fast-follow の状態表示を追加する

- Step 6 で作った STT セクションに、**Android の fast-follow DL状態・進捗・再試行ボタン**を追加する。
- `bundletool` 経由で「未到着 → DL中 → 完了」の遷移と再試行を、目で確認できるようにする。

### 6. 本物経路とマニフェストを確認する

- `bundletool --local-testing` で**本物の fast-follow 経路**（DL → `getPackLocation`）を再現して通す。
- ビルド後の**最終 AndroidManifest** に PAD 由来の `INTERNET`／`ACCESS_NETWORK_STATE` が入ること、runtime ダイアログ権限は `RECORD_AUDIO` のみであることを確認する（詳細は次節）。

---

## オフラインと権限（fast-follow に伴う整理）

「完全オフライン」「`INTERNET` 不要」は VAD・マイクの文脈で書いてきたが、NeMo を fast-follow で配ると **Android だけ前提が一段変わる**。混乱しないよう切り分ける。

- **実行時は完全オフライン（両OS）**: 音声認識も VAD も、モデルさえ端末にあれば**推論にネットは要らない**。ここは従来どおり。
- **Android の NeMo 入手だけ初回に一度ネットを使う**: fast-follow は初回に Play が1回だけDLする。**PAD（`asset-delivery` ライブラリ）を入れると、その manifest 由来で `INTERNET`＋`ACCESS_NETWORK_STATE` がマニフェストマージで自動的に付く**。＝「Android は `INTERNET` 不要」は NeMo 配信を入れた時点で成り立たない。
- **ユーザーに見える権限ダイアログは増えない**: `INTERNET`／`ACCESS_NETWORK_STATE` は **normal permission**（インストール時に自動付与）なので許可ダイアログは出ない。ダイアログが出るのはマイクの `RECORD_AUDIO`（runtime 権限）だけで、従来どおり。レイヤーが違う。
- **silero・マイクの「ローカル／`RECORD_AUDIO` のみ」は今も正しい**: silero はローカルなので VAD のための `INTERNET` は不要、マイクは `RECORD_AUDIO` のみ。NeMo の `INTERNET` はそれとは独立に増えるもの。
- **iOS は丸ごとオフライン**: NeMo も同梱でDLが無いため、インストール以降は入手も実行も完全オフライン・追加権限なし。

---

## このステップでやらないこと

- スプラッシュの「準備中」表示（準備状態を**消費**する側） → Step 9
- 音声入力の**準備待ちガード**（準備状態を消費する側） → Step 10
- iOS の NeMo 配信（Step 6 のバンドルリソースで**完了済み**）
- **Android のストア公開対応（fast-follow パックの申請設定の作り込み）** → リリース準備時に別途

---

## 完了の目安

- 実機（`bundletool --local-testing` 経由）で、fast-follow の **DL → `getPackLocation` 実パス取得**が通る。
- dev catalog で fast-follow の**DL状態・進捗・再試行**が確認でき、「未到着 → 完了」の遷移が見える。
- パス契約の Android 実装が、本番では fast-follow 実パス、dev では事前配置と**両対応**になっている。
- 最終 AndroidManifest に PAD 由来の `INTERNET`／`ACCESS_NETWORK_STATE` が入り、runtime ダイアログ権限は `RECORD_AUDIO` のみ。
- `flutter analyze` が通る。

---

## 関連ドキュメント

- [step06_provision_models.md](step06_provision_models.md) — 配置とパス契約の土台（このステップはその Android 実装を本番化する）
- [model_distribution.md](model_distribution.md) — 配布方式の詳細（iOS/Android 差・PAD・ストア申請）
- [../research/on_device_stt/model_delivery_flutter_impl.md](../research/on_device_stt/model_delivery_flutter_impl.md) — 実装手段（薄い自前ブリッジ）の調査・3案比較・サイズ上限
- [../research/on_device_stt/model_delivery_decision_for_beginners.md](../research/on_device_stt/model_delivery_decision_for_beginners.md) — fast-follow 採用の判断（やさしい解説）

---

## 作業チェックリスト

- [ ] `asset-delivery` 依存を追加し、fast-follow アセットパック用の小モジュールを `settings.gradle.kts` / `build.gradle.kts` に紐付け
- [ ] `AssetPackManager` の薄いネイティブブリッジ（`getPackLocation` 実パス・`getPackStates`/listener 状態進捗・`fetch`/再試行）を実装し、Dart へ橋渡し
- [ ] パス契約の Android 実装を「事前配置」→「fast-follow 実パス」に差し替え（dev は事前配置と両対応）
- [ ] provisioner に準備状態（未開始／DL中／完了／失敗）・進捗・`ensureReady()`・再試行を公開（消費は Step 9／10）
- [ ] dev catalog に Android の fast-follow DL状態・進捗・再試行ボタンを追加
- [ ] `bundletool --local-testing` で本物の fast-follow 経路（DL→`getPackLocation`）を確認
- [ ] 最終 AndroidManifest に PAD 由来の `INTERNET`／`ACCESS_NETWORK_STATE` が入ること、runtime ダイアログ権限は `RECORD_AUDIO` のみであることを確認
- [ ] `flutter analyze` が通る
