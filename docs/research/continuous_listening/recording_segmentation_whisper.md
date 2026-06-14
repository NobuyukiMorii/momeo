# 連続録音 → 無音区切り → Whisper チャンク処理の実装手段調査

## この文書について

- **目的**: `next_stt_approaches.md` で方向づけた **「A. オンデバイス Whisper ＋ 録音/テキスト化の分離」** を、実際に組むための具体的な部品（録音パッケージ・無音検知/VAD・Whisper パッケージ・日本語モデル）まで掘り下げる。
- **調査日**: 2026-06-07
- **前提**: momeo は「**日本語が主**」「**常時リスニング（長時間）でメモ化**」「**プライバシー重視**」「**個人開発（低コスト）**」。
- **関連文書**: `continuous_listening_limitation.md`（なぜ現方式がダメか）, `next_stt_approaches.md`（次の方向づけ）, `speech_recognition_accuracy.md`（ストリーミング vs バッチ）, `on_device_llm.md`（整文の後処理）

---

## TL;DR（結論サマリ）

- **パイプラインの全体像はこうなる**:

  ```text
  ① 連続録音（record で PCM ストリームを途切れず取得）
     ↓
  ② 無音区切り（Silero VAD で発話の開始/終了を検出してチャンク化）
     ↓
  ③ Whisper でバッチ処理（チャンク単位でオンデバイス・テキスト化）
     ↓
  ④ 確定テキストを既存の接続点（ListeningPage の _addMemo）へ渡して保存
  ```

- **技術的にも「分離」は正しいと裏付けられた**: モバイルの **ストリーミング Whisper は遅すぎる**（Android で 1秒の音声処理に約5〜7秒かかる報告）。一方 **バッチ処理は速い**。つまり「録音は連続・テキスト化は後からチャンク単位」という分離は、性能面でも理にかなっている。
- **日本語にとって最重要の事実**: 標準 Whisper の **tiny / base は日本語では実用外**（ReazonSpeech テストで WER 約 58% / 28%）。**最低でも small（約 16%）**、本命は **日本語特化の `kotoba-whisper`（約 12%）**。しかも kotoba-whisper は **ggml 形式が公開済み**で whisper.cpp 系からそのまま使える。
- **VAD の発話区切りが、そのままメモカードの区切りになる**。`listening_flow.md` で `speech_to_text` の `onStatus='done'` に頼っていた「確定トリガー」を、**VAD の発話終了（onSpeechEnd）**に置き換えられる。
- **現実的なスタックは2案**: ①`sherpa_onnx` 統合型（VAD＋Whisper を1エンジンで）、②`whisper.cpp` 個別組み立て型（日本語特化モデルを直接使える）。
- **最大の未解決リスクは「常時バックグラウンド録音」**: Android はフォアグラウンドサービス必須、iOS は背景録音は可能だが **App Review の審査が厳しく**、電池・発熱・マイク使用インジケーター常時表示という現実が付いて回る。

---

## 1. 全体アーキテクチャ

### パイプラインと各段の役割

| 段 | 役割 | 担当部品の候補 |
|---|---|---|
| ① 連続録音 | マイクを掴みっぱなしで PCM を途切れず取得（**空白ゼロ**） | `record` / `flutter_sound` |
| ② 無音区切り | 発話の開始・終了を検出してチャンク化 | Silero VAD（`vad` パッケージ or `sherpa_onnx` 内蔵） |
| ③ テキスト化 | チャンクを **バッチ**で Whisper にかける | `whisper_ggml` 系 / `sherpa_onnx` |
| ④ 保存 | 確定テキストをメモとして永続化 | 既存の `VoiceMemoRepository`（drift） |

### 既存コードとの接続点（重要）

本リポジトリは既に **「テキスト化の方式を問わない接続点」** を用意できている。新方式はこの2点に差し込むだけで載る。

- [listening_page.dart](lib/pages/listening_page.dart) の `_addMemo(String text)` … コメントにも *「音声のテキスト化が済んだら、ここに確定テキストを渡す（方式を問わない接続点）」* とある。④の出口はここ。
- [voice_memo_repository.dart](lib/repositories/voice_memo_repository.dart) … drift による保存。`insert(content, createdAt)` がそのまま使える。

→ つまり **①〜③のパイプラインを新規に作り、出力を `_addMemo` に渡す**のが実装の骨子。`speech_to_text` は現状 dev カタログの観察用セクション（[packages_speech_to_text_section.dart](lib/pages/dev/catalog/sections/packages/packages_speech_to_text_section.dart)）にしか組み込まれておらず、本番フローには未接続なので、置き換えではなく**新規追加**になる。

---

## 2. 段①: 連続録音

### パッケージ比較

| パッケージ | PCM ストリーム | 成熟度 | 備考 |
|---|---|---|---|
| **`record`** | ✅（file or stream、複数コーデック） | ◎ | **Flutter 公式が録音用途で推奨**。背景録音のドキュメントあり |
| **`flutter_sound`** | ✅（PCM Float32 / Int16 のストリーム） | ◎ | 老舗。ストリーム配信が主機能 |

どちらも「マイク → PCM ストリーム」を連続供給でき、①の要件（途切れない録音）を満たす。**`record` を第一候補**とする（公式推奨・API がシンプル）。

### 連続キャプチャの制約（最重要・実運用の壁）

「常時リスニング」を名乗る以上、画面を離れても録り続けたいが、ここに OS の壁がある。

- **Android**: 既定ではマイク取得は **約60秒で打ち切られる**（OEM・電池最適化で変動）。連続取得には **フォアグラウンドサービス**が必須。
  - `flutter_foreground_task` を使い、Android 14+ では `FOREGROUND_SERVICE_MICROPHONE` 権限とサービスタイプ `microphone` を `AndroidManifest.xml` に設定。
  - 通知バーに常駐通知が出る（OS 仕様）。
- **iOS**: `Info.plist` の `UIBackgroundModes` に `audio` を追加すれば**背景でも録音継続は可能**。ただし、
  - ユーザーがアプリスイッチャーから**スワイプで終了するとアプリは kill** される。
  - **App Review が背景マイクアクセスを厳しく審査**する。「アプリの主目的に不可欠であること」を明確に正当化する必要があり、監視・データマイニング目的とみなされると**リジェクト**される。
  - iOS 14 以降、マイク使用中は**常にインジケーター（オレンジ点）が表示**される（Android も緑点）。これは「常に聞いている」アプリの**プライバシー UX として正面から向き合う**べき点。

→ **「画面を開いている間だけリスニング」**か **「真の常時バックグラウンド」**かで難易度が大きく変わる。前者なら背景制約をほぼ回避でき、まずはここから始めるのが現実的。

---

## 3. 段②: 無音区切り（VAD）

### なぜ単純な音量しきい値ではなく VAD か

「一定音量以下が続いたら無音」という素朴なしきい値方式は、環境ノイズ・声の大小・無声子音で誤判定しやすい。**Silero VAD**（学習済みの軽量 VAD モデル）は雑音耐性が高く、発話の開始/終了を安定して検出できる。Whisper のチャンク境界はここの精度に直結するので、VAD を使う価値は大きい。

### VAD パッケージの候補

| 候補 | 中身 | 特徴 |
|---|---|---|
| **`vad` パッケージ** | Silero VAD v4/v5 を ONNX Runtime に FFI バインド | iOS/Android/Web/デスクトップ対応。`onSpeechStart` / `onSpeechEnd` / `onRealSpeechStart`（ミスファイア除外）/ `onFrameProcessed` などのイベントを発火 |
| **`sherpa_onnx` 内蔵 VAD** | Silero VAD を同梱 | ②と③を**同一エンジンで**まかなえる（後述スタックA） |

### 重要な気づき1: VAD の発話区切り ＝ メモカードの区切り

momeo は「発話ごとに1枚のメモカード」を作る（[listening_flow.md](docs/specs/listening_flow.md)）。VAD の **発話終了（onSpeechEnd）が、そのまま「カード確定トリガー」**になる。

- これまで `speech_to_text` の `pauseFor=1.5秒 → onStatus='done'` で確定していた仕組みを、**VAD の発話終了に置き換えられる**。
- つまり VAD は「チャンク境界の決定」と「メモ確定の合図」を**一石二鳥**でこなす。→ `listening_flow.md` の確定条件の節は、新方式向けに**改訂が必要**（後述）。

### 重要な気づき2: マイクの「所有者」を1つにする

`vad` パッケージは**自前でマイクを掴む**実装になっている。①の `record` と同時にマイクを開くと**二重キャプチャ**になりかねない。設計は次のどちらかに寄せる。

- **VAD にマイクを持たせる**: `vad` パッケージが連続キャプチャしつつ発話を切り出し、`onSpeechEnd` で得た音声サンプルを Whisper に渡す（部品が減ってシンプル）。
- **`record` にマイクを持たせる**: `record` の連続 PCM ストリームを、マイクを持たない VAD（`sherpa_onnx` の VAD など）に**流し込んで**境界を判定する（スタックAと相性が良い）。

いずれの場合も **マイクは開きっぱなし**なので、`continuous_listening_limitation.md` で問題になった「**認識器の再起動による空白**」は構造的に発生しない（あの空白は“マイク”ではなく“認識セッション”の再起動が原因だった）。

---

## 4. 段③: Whisper でチャンク処理

### 重要な気づき: モバイルでは「バッチ」一択（ストリーミングは遅すぎる）

whisper.cpp のモバイル実測では、**ライブ（ストリーミング）処理は約5〜7秒かけて1秒分を処理**するほど遅い一方、**バッチ処理は十分速い**という報告がある。これは本方針の核心を裏付ける:

> Whisper をリアルタイムに回そうとしてはいけない。**VAD で切り出したチャンクを、後からまとめて（バッチで）処理**するのが正解。

数秒の遅延を許容できる momeo の「メモ化」用途とは相性が良い。

### Whisper パッケージの候補

| パッケージ | 方式 | 特徴 |
|---|---|---|
| **`whisper_ggml` / `whisper_ggml_plus`** | whisper.cpp（ggml） | ファイルベースのバッチ転写。`_plus` は whisper.cpp v1.8.3・Large-v3-Turbo 対応 |
| **`whisper_flutter_new`** | whisper.cpp（ggml） | 99言語・オンデバイス。`next_stt_approaches.md` で既出 |
| **`whisper_kit`** | WhisperKit 系 | 99言語・SRT/VTT 書き出し・バッチ |
| **`sherpa_onnx`** | ONNX Runtime | VAD＋Whisper＋他 ASR を1パッケージで。日本語含む多言語・完全オフライン・iOS/Android。v1.13.2 が活発に更新 |

### 日本語モデルの選定（最重要）

ここが今回の調査で**最も実装判断を左右する**ポイント。標準 Whisper のモデルサイズ別 日本語 WER（ReazonSpeech テストセット、参考値）:

| モデル | パラメータ | 日本語 WER（目安） | 評価 |
|---|---|---|---|
| Whisper **tiny** | 39M | **約 58%** | **日本語では実用外** |
| Whisper **base** | 74M | **約 28%** | 厳しい |
| Whisper **small** | 244M | **約 16%** | ここから実用圏 |
| **kotoba-whisper** v1.0/v2.0 | large-v3 蒸留 | **約 12%** | **本命**。large-v3 比 6.3倍速で精度は同等水準 |

→ `next_stt_approaches.md` には「最小70MB〜（tiny/base/small）で実用」とあったが、**日本語に限れば tiny/base は精度が足りない**。日本語が主の momeo では **small 以上、できれば `kotoba-whisper`** を選ぶべき。

**そして決定的に重要なのは、`kotoba-whisper` が ggml 形式（`kotoba-whisper-v1.0-ggml` / `v2.0-ggml` / `bilingual-v1.0-ggml`）で公開済み**ということ。これは whisper.cpp 系パッケージ（`whisper_ggml` / `whisper_flutter_new` 等）で**そのまま読み込める**。`sherpa_onnx` で使うなら ONNX へのエクスポートがひと手間必要。

### モデルサイズ・端末負荷

- ggml の目安: base ≈ 142MiB、実行時 RAM ≈ 388MB。tiny/base は 1GB RAM で動作。
- **量子化（q5_0 / q4 等）**でサイズ約45%減・遅延約19%減が可能。モバイルでは量子化版が前提。
- 配布方法: **アプリ同梱**（サイズ増）か **初回ダウンロード**（初回 UX 配慮）かの選択になる。

---

## 5. 実装スタックの2案

### スタックA: `sherpa_onnx` 統合型（部品が少ない）

```text
record（連続PCM） → sherpa_onnx VAD（Silero） → sherpa_onnx Whisper（ONNX） → _addMemo
```

- **長所**: VAD と ASR を**1エンジン**でまかなえる。依存が少なく、PCM の受け渡しが素直。完全オフライン・活発に更新。
- **短所**: 日本語精度を `kotoba-whisper` 水準にするには **ONNX エクスポートの手間**が要る。同梱の標準 Whisper（多言語）だと日本語精度は一段落ちる。

### スタックB: `whisper.cpp` 個別組み立て型（日本語精度が出しやすい）

```text
record or vad（連続キャプチャ＋発話切り出し） → whisper_ggml/whisper_flutter_new（kotoba-whisper-v2.0-ggml 量子化） → _addMemo
```

- **長所**: **`kotoba-whisper-ggml` をそのまま使えて日本語精度が最も出やすい**。各部品が枯れている。
- **短所**: 録音・VAD・Whisper を**個別に結線**する必要がある。マイク所有者の整理（§3）が要る。

### 比較

| 観点 | スタックA（sherpa_onnx 統合） | スタックB（whisper.cpp 個別） |
|---|---|---|
| 統合の手間 | ◎ 1パッケージ | △ 3部品を結線 |
| 日本語精度の出しやすさ | △ ONNX 変換が要る | ◎ kotoba-whisper-ggml が即使える |
| オフライン/プライバシー | ◎ | ◎ |
| 成熟度 | ○ | ○〜◎ |

---

## 6. 主要リスクと未検証事項

- **iOS の常時バックグラウンド録音 × App Review**（最大リスク）: 背景マイクは技術的に可能でも審査が厳しい。まず**「アプリ表示中のみリスニング」**に割り切り、真の常時化は別途検討する判断もあり得る。
- **電池・発熱**: 常時録音 ＋ 定期的な Whisper 推論は負荷が高い。量子化モデル・チャンク単位処理・端末性能での出し分けが要る。
- **モデル配布**: 同梱（アプリサイズ増）か初回 DL（初回 UX）か。
- **`listening_flow.md` の改訂**: 確定条件が `speech_to_text` の `pauseFor / onStatus='done'` 前提になっている。新方式では **VAD の `onSpeechEnd` を確定トリガー**にする形へ書き換えが必要。
- **整文（LLM 後処理）との組み合わせ**: `on_device_llm.md` の方針（確定後にオンデバイス LLM で整文）は、本パイプラインの④の直後に**そのまま接続できる**。Whisper の生出力 → 整文 → 保存、という段を将来足せる。
- **未実測の数値**: 本書の日本語 WER・速度は文献値。**実機（Pixel 8a / iPhone）でのチャンク長・遅延・電池・精度は要実測**。

---

## 7. 結論と次の一手

### 結論

- **方向性（録音/テキスト化の分離）は技術的にも妥当**。モバイルではストリーミング Whisper が遅く、**バッチ＋VAD 区切り**が正解。
- **日本語が主**である以上、モデルは **small 以上、本命は `kotoba-whisper`**。tiny/base は不可。
- **`kotoba-whisper-ggml` が即使える**点で、まずは **スタックB（whisper.cpp 個別）** が精度検証の入口として有利。`sherpa_onnx`（スタックA）は統合の手軽さで対抗。

### 次の一手（提案する検証順）

1. **精度スパイク**: `whisper_ggml`（or `whisper_flutter_new`）で **`kotoba-whisper-v2.0-ggml`（量子化）** を読み込み、手元の日本語音声ファイルをバッチ転写して**精度と速度を実測**。
2. **VAD スパイク**: `vad` パッケージで連続マイク → `onSpeechEnd` でチャンク切り出し → 1 のスパイクに流す。発話区切りの体感を確認。
3. **結線**: ②→①の順で繋ぎ、出力を `_addMemo` に渡して**端から端まで**動かす（まずはアプリ表示中のみ）。
4. **比較検証**: 余力があれば `sherpa_onnx` 統合型でも同じ音声を回し、統合の手軽さ vs 日本語精度を比較。
5. **仕様反映**: 動いたら `listening_flow.md` を「VAD の発話終了で確定」へ改訂。

---

## 8. 関連ドキュメント

- `docs/research/continuous_listening/continuous_listening_limitation.md` — `speech_to_text` の限界（再起動の空白）
- `docs/research/continuous_listening/next_stt_approaches.md` — 次の方向づけ（オンデバイス Whisper ＋ 分離）
- `docs/research/speech_recognition_accuracy.md` — ストリーミング vs バッチの精度差
- `docs/research/on_device_llm.md` — 確定後の整文（オンデバイス LLM 後処理）
- `docs/specs/listening_flow.md` — 確定条件は新方式向けに改訂が必要

## 参考リンク

### 録音・VAD
- [record | pub.dev](https://pub.dev/packages/record)
- [flutter_sound | pub.dev](https://pub.dev/packages/flutter_sound)
- [vad（Silero VAD v4/v5）| pub.dev](https://pub.dev/packages/vad)
- [Silero VAD | GitHub](https://github.com/snakers4/silero-vad)
- [flutter_foreground_task | pub.dev](https://pub.dev/packages/flutter_foreground_task)
- [Record or stream audio input — Flutter Docs](https://docs.flutter.dev/cookbook/audio/record)

### Whisper（オンデバイス）
- [sherpa_onnx | pub.dev](https://pub.dev/packages/sherpa_onnx)
- [whisper_ggml | pub.dev](https://pub.dev/packages/whisper_ggml)
- [whisper_ggml_plus | pub.dev](https://pub.dev/packages/whisper_ggml_plus)
- [whisper_flutter_new | pub.dev](https://pub.dev/packages/whisper_flutter_new)
- [whisper_kit | pub.dev](https://pub.dev/packages/whisper_kit)
- [whisper.cpp | GitHub](https://github.com/ggml-org/whisper.cpp)
- [whisper.cpp Discussion #3567 — Android のストリーミングは実時間の約5倍遅い／バッチは速い](https://github.com/ggml-org/whisper.cpp/discussions/3567)
- [Export Whisper to ONNX — sherpa docs](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/export-onnx.html)

### 日本語モデル（kotoba-whisper）
- [kotoba-tech/kotoba-whisper-v2.0 | Hugging Face](https://huggingface.co/kotoba-tech/kotoba-whisper-v2.0)
- [kotoba-tech/kotoba-whisper-v2.0-ggml | Hugging Face](https://huggingface.co/kotoba-tech/kotoba-whisper-v2.0-ggml)
- [kotoba-tech/kotoba-whisper-v1.0-ggml | Hugging Face](https://huggingface.co/kotoba-tech/kotoba-whisper-v1.0-ggml)
- [kotoba-whisper | GitHub](https://github.com/kotoba-tech/kotoba-whisper)

### モデルサイズ・性能
- [Whisper Model Sizes Explained — OpenWhispr](https://openwhispr.com/blog/whisper-model-sizes-explained)
- [Quantization for OpenAI's Whisper Models（量子化）| arXiv](https://arxiv.org/html/2503.09905v1)
- [Running Transcription Models on the Edge — ionio.ai](https://www.ionio.ai/blog/running-transcription-models-on-the-edge-a-practical-guide-for-devices)

### バックグラウンド・権限
- [audio_service | pub.dev](https://pub.dev/packages/audio_service)
- [Background modes — GetStream（iOS/Android 背景音声）](https://getstream.io/video/docs/flutter/advanced/background-modes/)
