# オンデバイス STT：検証（スパイク）と計画調整の進め方

## この文書について

- **位置づけ**: `outline.md`（マスター計画）を確定・修正する前に、**まだ実証できていない前提**を「使い捨てブランチでの検証（スパイク）」で確かめ、その結果で計画を調整するための運用ルールと、**いま行う検証の概要・ステップ**をまとめる。
- **このディレクトリ（`docs/on_device_stt/verification/`）の役割**: 計画を変える根拠となる検証を、**結果まで含めて記録**する場所。ここでの合否で `outline.md` の改訂可否を判断する。
- **運用ルール（簡潔に）**:
  - **1検証 = 1ファイル**（`NN_<topic>.md`）。本書はその一覧と運用方針を兼ねる。今回の検証#01 は本書に直接記載する。
  - 各検証は「**目的／なぜ今／合格条件／手順／結果／結論**」を持つ。
  - スパイクのコードは**使い捨て**（ブランチごと破棄してよい）。**残すのは知見＝この docs だけ**。
  - **合格 → `outline.md` と各 step を改訂**。**不合格 → フォールバック方針を採用**し、その理由を記録する。

---

## なぜ今これをやるのか（現在地）

- `outline.md` の現計画は **`vad` パッケージ前提**で書かれている。
- しかし調査の結果、**案C（`sherpa_onnx` 内蔵の Silero VAD ＋ `record` で録音）** の方が本質的にクリーンだと分かった。
  - onnxruntime が sherpa の1本だけになる（`libonnxruntime.so` の二重同梱が**そもそも起きない** → pickFirst も exclude も不要）。
  - **iOS を 13.0 のまま維持**できる（15.1 を要求していたのは `vad` の onnxruntime-objc だけ。`sherpa_onnx_ios` は xcframework 同梱で onnxruntime-objc 非依存、`record_ios` は 12.0）。
  - silero_vad.onnx をローカルパスで渡せるため **INTERNET 権限不要・完全オフライン**（道1 同梱と一致）。
- **唯一の未実証点**は「**`record` → バッファ → sherpa 内蔵 VAD → `OfflineRecognizer`（`nemoCtc`）の配線**」が本リポジトリで素直に回り、区切り品質が従来（`vad` パッケージ）同等か、という1点だけ。
  - エンジン（sherpa）・モデル（NeMo CTC / Silero VAD）は research で実証済み・**同一**。**差分は“配線”だけ**。
- → **docs を書き直す前に、この“配線”だけをスパイクで確かめる。**

---

## 検証一覧

| # | 検証 | 状態 | 記載場所 |
|---|---|---|---|
| 01 | 案C：sherpa 内蔵 VAD ＋ `record` の配線が成立するか | **未着手** | 本書（下記） |

---

## 検証 #01：案C の配線スパイク

### 目的

案C の配線（録音 → 区切り → 文字化）を**最小構成**で組み、下の合格条件を満たすか確かめる。
**合格なら案C で計画を確定、不合格なら案A（`vad` ＋ pickFirst）へ戻す。**

### ステップ

| # | 内容 | 補足 |
|---|---|---|
| 0 | **退避（ユーザーが実施）**: 現在の未コミット差分を `stash` | 検証を素の状態から始めるため |
| 1 | **検証ブランチを切る**: `research/stt-sherpa-builtin-vad`（使い捨て） | コードは後で破棄してよい |
| 2 | **依存を一時追加**: `pubspec.yaml` に `sherpa_onnx: ^1.13.2` と `record: ^6.x`（**`vad` は入れない**）→ `flutter pub get` | onnxruntime が1本になることの実証材料 |
| 3 | **モデルを暫定配置**: research と同様に `adb push` で NeMo（`model.int8.onnx` ＋ `tokens.txt`）と `silero_vad.onnx` を内部ストレージへ | 本配布（Step 5）は先取りしない |
| 4 | **最小ループを実装**: dev catalog に一時セクションを作り、`record`（PCM16 / 16kHz / mono）のストリーム → CircularBuffer → `VoiceActivityDetector`（Silero）で区切り → `OfflineRecognizer`（**`nemoCtc`**）で文字化 → 画面に結果と所要時間を表示 | 公式例 `flutter-examples/non_streaming_vad_asr` を参照。**モデル種別は必ず `nemoCtc`（単一ファイル CTC）**。`transducer`（3ファイル）と混同しない |
| 5 | **合否を判定**: 下の合格条件で評価 | |
| 6 | **反映**: 合格 → `outline.md`・各 step を案C前提に改訂し、本書の「結果」に記録、スパイクは破棄。／ 不合格 → 案A を継続し理由を記録 | |

### 合格条件（ゲート）

- [ ] `flutter pub get` が解決する（`sherpa_onnx` ＋ `record` が既存の `permission_handler ^12` / `flutter_riverpod 3` と衝突しない）
- [ ] **Android ビルドが通る**：pickFirst / exclude を**一切入れず**に `libonnxruntime.so` 衝突が出ない（＝onnxruntime 1本の実証）
- [ ] **iOS が deployment target 13.0 のまま** pod install / build できる（できれば iOS 13/14 の実機かシミュレータで起動確認）
- [ ] **機能**：実機（例 Pixel 8a）で 録音 → VAD 区切り → NeMo CTC が妥当な日本語テキストを返す
- [ ] **区切り品質**：発話の取りこぼし・語尾切れが従来（`vad` パッケージ）同等以上（転写速度はエンジン不変なので従来どおり ~110〜280ms/発話のはず）
- [ ] **VAD モデルが完全ローカル**（`silero_vad.onnx`・INTERNET 不要）で動く
- [ ] マイクは **`RECORD_AUDIO` のみ**で取得できる（`MODIFY_AUDIO_SETTINGS` 不要を確認）

### 結果（検証後に記入）

（未記入）

### 結論（検証後に記入）

（未記入：採用＝案C／フォールバック＝案A）

---

## 合否後の進め方（ドキュメントへの影響）

- **合格（案C 確定）**:
  - `outline.md`：「採用が決まっていること」を “区切り＝sherpa 内蔵 Silero VAD（`vad` パッケージは不採用）” に修正。**Step 3 を縮小**（.so 二重同梱対策・iOS 15.1・INTERNET/MODIFY_AUDIO を削除）。**Step 4 を書き換え**（`record` の PCM stream → CircularBuffer → sherpa VAD で区切り）。**Step 5 に `silero_vad.onnx`（~2MB）同梱を追記**。
  - `step01` / `step02`：完了済みで影響は軽微（むしろマイクのみ・INTERNET 不要と整合が強まる）。必要なら一行注記。
  - `step03`：案C前提に全面書き直し。旧 `vad` 前提の知見（pickFirst / exclude / iOS15.1）は**歴史メモ**として残す。
- **不合格（案A 継続）**:
  - `outline.md` / `step03` はほぼ現行維持（A 主・B 併記）。本書の「結果」に不合格理由を記録する。

---

## 関連ドキュメント

- [outline.md](../outline.md) — マスター計画（実装ステップ全体）
- [model_distribution.md](../model_distribution.md) — モデル配布の詳細
- [vad_whisper_impl_log.md](../../research/on_device_stt/vad_whisper_impl_log.md) — エンジン／モデル選定の実証記録（NeMo・Silero の根拠）
