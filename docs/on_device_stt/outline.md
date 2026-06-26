# オンデバイス STT 実装計画

## この文書について

- **目的**: 調査（`docs/research/on_device_stt/`）と検証（`docs/on_device_stt/verification/`）で固まった方針を、本番実装へ落とし込むための作業計画をまとめる。
- **進め方**: `main` 上で進める。**1 step = 1 commit = 1つの明確な目的**になるよう分割する。
- **記載方針**: 具体的なソースコードは書かない。各ステップの「目的・やること・完了の目安」を言葉で表す。
- **検証方法**: 各レイヤーの動作確認は dev catalog（`lib/pages/dev/catalog`）に**恒久的な検証セクション**を追加して行う。
- **前提の裏取り**: 本計画の中核（sherpa 内蔵 VAD + record の配線）は、使い捨てブランチ `research/stt-sherpa-builtin-vad` で実機実証済み。合否と根拠は `docs/on_device_stt/verification/README.md` を参照。

---

## 採用が決まっていること（前提）

- **エンジン**: `sherpa_onnx` + 日本語モデル **NeMo parakeet CTC 0.6B**（int8 単一ファイル 約625MB ＋ tokens）。
  - 精度オンデバイス最高・句読点あり・体感ゼロ遅延（実機で約75〜215ms/発話）。決定経緯は `docs/research/on_device_stt/vad_whisper_impl_log.md` 参照。
- **録音**: `record` パッケージでマイクを連続キャプチャし、**PCM ストリーム（16bit / 16kHz / モノラル）**を取得する。
- **区切り**: `sherpa_onnx` に**内蔵された Silero VAD** で発話の開始・終了を検出する（モデル `silero_vad.onnx` 約2MB をローカル同梱）。
- **不採用**:
  - `vad` パッケージ … sherpa 内蔵 VAD で代替できるため使わない（理由は次節）。
  - whisper（`whisper_flutter_new`）… 速度で完敗のため本番に持ち込まない。
  - Vosk … ライブ感はあるが精度最下位で不採用。
- **接続点**: リスニング画面 `lib/pages/listening_page.dart` には方式非依存の `_addMemo(String)` が既にある。最終的にここへ確定テキストを渡す。

---

## なぜ「sherpa 内蔵 VAD + record」なのか

区切りは `vad` パッケージでも実現できるが、本計画では **`sherpa_onnx` 内蔵の Silero VAD ＋ `record`** を採る。理由は、ネイティブの土台が本質的にクリーンになるため（いずれも実機・実物で確認済み）。

- **onnxruntime が1本になる**: `sherpa_onnx` も `vad` も内部で onnxruntime を使う。両方入れると Android で `libonnxruntime.so` が**二重同梱**してビルドが壊れる。`vad` を使わなければ onnxruntime は **sherpa の1本だけ**になり、重複対策（pickFirst / exclude）が**そもそも不要**になる。
- **iOS を 13.0 のまま維持できる**: 15.1 を要求していたのは `vad` が依存する `onnxruntime-objc` だけ。`sherpa_onnx_ios` は xcframework 同梱で onnxruntime-objc に非依存（podspec は iOS 13.0）、`record_ios` は 12.0。よって**デプロイメントターゲットの引き上げが不要**で、iOS 13/14 端末のサポートも維持できる。
- **VAD はオフライン**: `silero_vad.onnx` をローカルパスで渡すため、`vad` パッケージのような**VAD モデルの初回DLが発生しない**。同梱（道1）方針と一致する（アプリ全体の `INTERNET` 要否は「モデルの配布方式」の節で整理）。
- **権限が最小**: マイク取得は **`RECORD_AUDIO` のみ**で足りる（`MODIFY_AUDIO_SETTINGS` 等は不要）。

> マイク所有者の整理: `record` だけがマイクを掴み、その PCM を「マイクを掴まない」sherpa 内蔵 VAD に流し込む形にする。録音器は1つに集約されるため、二重キャプチャは起きない。

---

## 全体パイプライン

```text
🎤 record でマイクを連続キャプチャ（PCM16 / 16kHz / モノラル）
  ↓ PCM を Float32 に変換し、一定窓ごとに供給
sherpa 内蔵 Silero VAD（発話の開始〜終了を検出）
  ↓ 発話チャンク（SpeechSegment）として切り出し
sherpa-onnx OfflineRecognizer（NeMo CTC）でバッチ文字化
  ↓
確定テキスト
  ↓ _addMemo に渡す
メモカードとして保存・表示
```

---

## モデルの配布方式

端末に届けるモデルは2つ：

| モデル | サイズ | 用途 |
|---|---|---|
| NeMo parakeet CTC 0.6B（`model.int8.onnx` ＋ `tokens.txt`） | 約 625MB | 文字化（ASR） |
| Silero VAD（`silero_vad.onnx`） | 約 2MB | 発話の区切り（VAD） |

配布は **「道1：アプリに同梱」を基本**とする。**iOS と Android で実装・申請設定が異なる**（Android は 200MB 制限のため Play Asset Delivery が必要）。NeMo が大きいので配布設計の主対象は NeMo、`silero_vad.onnx` は小さく普通のアセットに相乗りできる。

ただし **Android の NeMo（625MB）は、PAD の中でも `fast-follow`（インストール直後に Play が自動DL）を使う**。install-time だとコピー必須・ディスク約1.25GB・自前ネイティブが要るため、コピー不要でディスク半減の fast-follow に切り替えた。引き換えに「初回はDL中でモデルが未到着」という状態が生まれ、初回起動時の進捗表示・準備待ちが要る（Android 固有）。なお iOS の NeMo は **Xcode のバンドルリソース**として同梱し、`Bundle.main` の実パスを直接渡す（コピー不要）。

**オフラインと権限の整理**: 音声認識も VAD も、モデルが端末にあれば**実行時はネット不要＝完全オフライン**（両OS）。崩れるのは「Android の NeMo の入手」だけで、fast-follow は初回に一度 Play がDLする。**PAD（`asset-delivery` ライブラリ）を入れると、その manifest 由来で `INTERNET`＋`ACCESS_NETWORK_STATE` がマニフェストマージで自動付与**される＝「Android は `INTERNET` 不要」は NeMo 配信を入れた時点で成り立たない。ただし両者は **normal permission**（インストール時自動付与）なので**ユーザーに権限ダイアログは出ない**。マイクの `RECORD_AUDIO`（runtime 権限）とは別レイヤー。iOS は NeMo も同梱でDLが無く、入手も実行も完全オフライン・追加権限なし。

→ 配布方式の詳細は `docs/on_device_stt/model_distribution.md`、判断の経緯は `docs/research/on_device_stt/model_delivery_decision_for_beginners.md` を参照。

---

## 実装ステップ（各ステップ = 1コミット）

### Step 1: speech_to_text 関連の撤去 ✅ 完了済み

- **目的**: もう使わない `speech_to_text` の実装・依存を取り除き、クリーンな土台から始める。
- **やったこと**: `pubspec.yaml` から `speech_to_text` 依存を削除。dev catalog の観察セクションと登録を削除。未使用 import を整理。
- **完了の目安**: コードから `speech_to_text` への参照が消え、ビルドが通る。（案Cの影響なし）

### Step 2: 権限フローをマイク中心に整理 ✅ 完了済み

- **目的**: 音声認識権限を外し、「マイクのみ」のフローにする。
- **やったこと**: iOS の権限リストから音声認識権限（`Permission.speech`）を除去。`ios/Runner/Info.plist` の音声認識の利用目的記述を削除。権限画面の音声認識向け表示定義を削除。
- **完了の目安**: iOS・Android ともマイク権限のみを要求し、許可後にリスニングへ進む。
- **備考**: 案Cはこの方針をさらに補強する（VAD モデルがローカルなので **VAD のための** `INTERNET` は不要、マイクは `RECORD_AUDIO` のみ）。※ Android の NeMo 配信（fast-follow）では別途 `INTERNET` がマージされるが、normal 権限のため runtime ダイアログは増えない（「モデルの配布方式」の節を参照）。

### Step 3: `record` の追加とマイク取得の検証 ✅ 完了済み

- **目的**: 録音パッケージ `record` を入れ、マイクから PCM 音声を連続取得できることを確認する（区切り・文字化はしない）。
- **やること**:
  - `pubspec.yaml` に `record` を追加する（`sherpa_onnx` は次の Step 4）。
  - Android マニフェストの権限が **（この時点では）`RECORD_AUDIO` のみ**で足りることを確認する（NeMo の fast-follow を入れる Step 6 で PAD 由来の `INTERNET` 等が加わる）。
  - iOS のデプロイメントターゲットは **13.0 のまま据え置く**（`record_ios` は 12.0 対応のため引き上げ不要）。
  - dev catalog に検証セクションを追加し、録音開始/停止・受信サンプル数・音量メーターでマイク取得を可視化する。
- **完了の目安**: 検証セクションで、話すと音量メーターが反応し、PCM（16bit / 16kHz / モノラル）が連続取得できることを確認できる。
- **備考**: `record` は onnxruntime を含まないため `.so` 衝突とは無関係。モデルも不要なので、追加直後に単独で挙動確認できる。

### Step 4: `sherpa_onnx` の追加とネイティブビルドの土台 ✅ 完了済み

- **目的**: 推論エンジン `sherpa_onnx` を入れても、ビルドが通り起動する状態を作る（onnxruntime を sherpa の1本に保つ）。
- **やること**:
  - `pubspec.yaml` に `sherpa_onnx` を追加する（**`vad` は入れない**）。
  - 追加後もアプリがビルド・起動でき、Android で `libonnxruntime.so` の衝突が起きないことを確認する。
  - dev catalog に検証セクションを追加し、`initBindings()` でネイティブライブラリが読み込めることを表示する（区切り・文字化はモデル前提のため Step 5 以降）。
- **完了の目安**: 重複対策（pickFirst/exclude）を入れずにビルドが通って起動し、検証セクションでライブラリ読み込みが成功する。
- **備考**: 旧計画にあった「`.so` 二重同梱対策（pickFirst/exclude）」「iOS 15.1 への引き上げ」「`MODIFY_AUDIO_SETTINGS` の追加」は、`vad` を採用していたら必要だった対策で、案Cでは**いずれも不要**。（`INTERNET` も `vad` の VAD モデルDL用としては不要だが、Step 6 で NeMo の fast-follow を入れると PAD ライブラリ経由で別途付く。）

### Step 5: 録音と発話の区切り（録音層） ✅ 完了済み

- **目的**: Step 3 で確認した `record` のマイク取得に sherpa 内蔵 VAD をつなぎ、発話の開始〜終了を検出して「1発話分の音声データ」を取り出せるようにする（まだ文字化はしない）。
- **やること**:
  - Step 3 の `record` PCM ストリーム（16bit / 16kHz / モノラル）を Float32 に変換する。
  - サンプルを一定窓で VAD に供給し、発話チャンク（`SpeechSegment`）として受け取る仕組みを作る。
  - dev catalog に検証セクションを追加し、区切られた発話の件数・長さを表示する。
- **完了の目安**: 検証セクションで、話すたびに発話チャンクが1件ずつ区切られることを確認できる。

### Step 6: モデルの配置とパス契約（土台）

- **目的**: sherpa が読める**実ファイルのパス**を所定の場所に用意する**土台**を作る（メモリ読み込みは Step 9、Android の本番配信は Step 8）。
- **やること**:
  - **`silero_vad.onnx`（約2MB）**: 普通のアセットとして同梱し、初回起動で書込領域へ**コピー**する（Step 5 の流用）。
  - **NeMo（iOS）**: **Xcode のバンドルリソース**として同梱（4GB枠内）。`Bundle.main` の**実パスを直接渡す（コピー不要）**。Flutter アセットだと実パスが取れず 625MB のコピーが要るため避ける。
  - **NeMo（Android・この時点）**: 本番の fast-follow 配信は **Step 8**。本ステップでは **`adb push` の事前配置**で「決まったパスにモデルがある」状態を満たす（dev のみ）。
  - 「決まったパスに有効なモデルがある状態」を返す `SttModelProvisioner`（**パス契約**＝「決まった場所に必ず有効なモデルがある」という約束。届け方の違いはこの窓口の内側に隠し、使う側はパスだけ見る）を用意し、整合性（壊れ・未完了）を確認する。
  - dev catalog に検証セクションを追加し、各モデルのパス・サイズ・整合性を表示する。
- **完了の目安**: iOS は本物の同梱経路、Android は事前配置で、NeMo・tokens・silero_vad が所定パスに揃い、sherpa が実パスから読める。`flutter analyze` が通る。
- **備考**:
  - iOS をバンドルリソースにする理由（Flutter アセットだと 625MB コピーが要る）は `model_distribution.md` §3-1。
  - Android の本番配信（fast-follow）・初回DL未到着のUX・`INTERNET` の扱いは **Step 8** に分離した。
- **詳細**: `docs/on_device_stt/step06_provision_models.md` を参照。

### Step 7: sherpa-onnx による文字化（変換層）

- **目的**: 用意したモデルで、発話チャンクを日本語テキストに変換できるようにする（dev 事前配置の上で**エンジンの core を最速で実証**する）。
- **やること**:
  - NeMo CTC 構成（`nemoCtc`）で認識器を、パス契約（Step 6）の実パスから初期化する。
  - 発話チャンクを渡すとテキストが返る変換処理を実装する。
  - dev catalog に検証セクションを追加し、発話チャンクを文字化して結果と所要時間を表示する。
- **完了の目安**: 検証セクションで、発話チャンクから妥当な日本語テキストが返ることを確認できる。
- **備考**: 起動フローへの統合・アプリ全体で1個保持（シングルトン）は Step 9。ここでは dev catalog 上で単発に動けばよい。

### Step 8: Android fast-follow の本配信＋ネイティブブリッジ

- **目的**: 625MB の NeMo を**本番の Android** に届ける（最重・リスク隔離）。Step 6 の「事前配置」を本物の Play 配信に置き換える。
- **やること**:
  - `asset-delivery` 依存を追加し、**fast-follow アセットパック**用の小モジュールを定義して Gradle に紐付ける。
  - `AssetPackManager` を直接叩く**薄いネイティブブリッジ**を実装（`getPackLocation().assetsPath()` で実パス、`getPackStates`/listener で状態・進捗、失敗時 `fetch`/再試行）。既製の `asset_delivery` は on-demand 専用のため使わない。
  - パス契約の Android 実装を「事前配置」→「fast-follow 実パス」に差し替える（dev は事前配置と両対応）。
  - provisioner に**準備状態（未開始／DL中／完了／失敗）・進捗・再試行**を公開する（Step 9 のスプラッシュ／Step 10 の入力ガードがこれを消費する）。
  - `bundletool --local-testing` で本物の fast-follow 経路（DL→`getPackLocation`）を確認。ビルド後の最終 AndroidManifest に PAD 由来の `INTERNET`／`ACCESS_NETWORK_STATE` が入ること・runtime ダイアログ権限は `RECORD_AUDIO` のみであることを確認。
  - dev catalog に Android の fast-follow DL状態・進捗・再試行を表示する。
- **完了の目安**: 実機（bundletool 経由）で DL→実パス取得が通り、DL状態が dev catalog で確認できる。
- **備考**: 「`INTERNET` はマージされるが normal 権限でダイアログは増えない／実行時はオフライン」の整理、「512MB上限」誤情報の否定、3案比較は `model_distribution.md` と `docs/research/on_device_stt/model_delivery_flutter_impl.md`。ストア申請設定はリリース準備時に別途。
- **詳細**: `docs/on_device_stt/step08_android_fast_follow.md` を参照。

### Step 9: エンジンの読み込みを起動フローに組み込む（スプラッシュ＋シングルトン化）

- **目的**: Step 7 で動いた「エンジンをメモリに読み込む」処理を**起動フローに統合する**。起動のたびに必要なこの数秒を、スプラッシュ表示中に裏で済ませて待ち時間を感じさせず、さらにエンジンをアプリ全体で1つだけ保持する形にする（読み込みの仕組み自体は Step 7 で作成済み）。
- **やること**:
  - スプラッシュ開始と同時に、裏でエンジンの読み込み（モデルをメモリへ展開）を始める。
  - ただし初回起動で Android のモデルDL（625MB / fast-follow）がまだ終わっていない場合、スプラッシュの数秒では完了しない。メモリ読み込みは Step 8 の準備状態（`ensureReady`）が**完了してから**行い、進捗・準備中表示は Step 8 の状態を消費する。
  - アニメ終了時に読み込み済みなら次へ進み、未完了なら「準備中」を示して完了まで待ってから進む。
  - 読み込んだエンジンはアプリ全体で1つだけ保持して使い回す。
- **完了の目安**: 起動ごとにスプラッシュ中で読み込みが行われ、完了後にリスニング画面へ進む。長引いても画面が固まったように見えない。
- **詳細**: `docs/on_device_stt/step09_load_engine_on_splash.md` を参照。

### Step 10: リスニング画面への結線（エンドツーエンド）

- **目的**: 録音 → 区切り → 文字化 → 保存をつなぎ、話した内容がメモカードとして積まれるようにする。
- **やること**:
  - VAD の発話終了を確定トリガーとして、発話チャンクを sherpa で文字化し、結果を `_addMemo` に渡す。
  - Android でモデルが未準備なら、Step 8 の準備状態で**音声入力を始めさせないガード**を入れる。
  - アクティブカードに進行状況を、確定後は確定済みメモカードを表示する。
- **完了の目安**: 実機で話すと、確定テキストがメモカードとして保存・表示される（取りこぼしが起きにくいこと）。

### Step 11: 仕様ドキュメントの改訂

- **目的**: 実装に合わせて仕様文書を最新化する。
- **やること**:
  - `docs/specs/listening_flow.md` を「VAD の発話終了を確定トリガーとする／speech_to_text は廃止」前提に改訂。
  - `docs/specs/overview.md` 等の権限・フロー記述から音声認識権限の前提を更新。
- **完了の目安**: 仕様文書が新方式の実装と一致している。
