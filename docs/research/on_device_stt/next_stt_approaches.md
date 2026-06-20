# 次の音声テキスト化アプローチの調査

## この文書について

- **目的**: `speech_to_text`（OS標準のストリーミング認識）が常時リスニングに向かないと判明したため（`continuous_listening_limitation.md` 参照）、次に取りうる現実的な実装手段を整理する。
- **調査日**: 2026-06-07
- **対象**: ①オンデバイス STT エンジン ②録音 → 一括テキスト化、の2方向
- **前提**: momeo の特性は「**日本語が主**」「**常時リスニング（長時間）でメモ化**」「**プライバシー重視**（常に聞いている）」「**個人開発（低コスト）**」。

---

## TL;DR（結論サマリ）

- **最大の気づき**: 今回の根本問題（再起動の空白で取りこぼす）は、**録音とテキスト化を分離する**ことで構造的に解決できる。マイクを掴みっぱなしで連続録音すれば空白は生まれず、テキスト化は後から非同期で行えばよい。
- **方向性の軸は「オンデバイス Whisper」**。オフライン・無料・プライバシー良で、momeo のコンセプトと相性が良い。課題は端末負荷とモデルサイズ。
- **Picovoice Cheetah は不適**（日本語非対応・商用高額）。
- **クラウド STT** は高精度・実装簡単だが、「常に音声を送り続ける」プライバシーと通信コストが課題。

---

## 1. オンデバイス STT エンジン

| 候補 | 日本語 | 連続性 | 評価 |
|---|---|---|---|
| **Picovoice Cheetah** | ❌ 非対応（英仏独伊葡西のみ） | ◎ 真の連続・低遅延 | 日本語が主の momeo には**不適**。商用も高額（$6,000〜/年） |
| **オンデバイス Whisper**（`whisper.cpp` 系） | ✅ 99言語（日本語OK） | △ バッチ型（録音→処理） | **有力候補** |

### オンデバイス Whisper の現実

- **パッケージ候補**: `whisper_flutter_new` / `whisper_kit` / `whisper_ggml_plus` / `whisper_flutter_coreml`（iOS は CoreML/ANE で最大3倍速）
- **モデルサイズ**: 最小 70MB〜（tiny / base / small）。アプリ同梱 or 初回ダウンロード
- **速度**: 数秒の遅延を許容すれば base / small で実用。Pixel 7 Pro 等で動作実績あり
- **本質**: バッチ型（リアルタイムではない）。録音した音声をまとめて処理する

---

## 2. 録音 → 一括テキスト化

| 方式 | 精度 | 日本語 | コスト | 主な懸念 |
|---|---|---|---|---|
| **オンデバイス Whisper** | 高 | ✅ | 無料 | 端末負荷・モデルサイズ |
| **OpenAI Whisper API**（クラウド） | 最高 | ✅良好 | 従量 | 通信・プライバシー |
| **Deepgram Nova**（クラウド） | 高・高速 | ✅ | 安い（$0.0043/分〜） | 同上 |
| **Google STT**（クラウド） | 高 | ✅（73言語） | 従量 | 同上 |

---

## 3. 最大の気づき: 録音とテキスト化を「分離」する

今回の `speech_to_text` の根本問題は「**認識中にしか録音できず、再起動の空白で取りこぼす**」ことだった。

新方式の本質は、**録音とテキスト化を分けること**にある。

```text
マイクを掴みっぱなしで連続録音（取りこぼしゼロ）
↓
無音などで区切る
↓
区切った音声チャンクを Whisper（オンデバイス or クラウド）でテキスト化（非同期）
```

録音はマイクを離さないため**空白が生まれない**。テキスト化は後から落ち着いて処理できる。これにより、今回ぶつかった「再起動の切れ目で取りこぼす」問題を**構造的に解決**できる。

---

## 4. 結論と今後の方向性

### 現実的な2つの道

- **A. オンデバイス Whisper**: オフライン・無料・プライバシー◎。常時リスニングの momeo と相性が良い。課題は端末負荷とモデルサイズ。
- **B. クラウド STT（Deepgram 等）**: 実装が簡単・高精度・安価。ただし「常に音声を送り続ける」プライバシーと通信コストが課題。

### 方向性

momeo は「**常時リスニング × プライバシー × 個人開発（低コスト）**」のため、軸は **A（オンデバイス Whisper）＋「録音/テキスト化の分離」** とする。

→ 次は、A の方向で「連続録音 → 無音区切り → Whisper でチャンク処理」の具体的な実装手段（録音パッケージ、無音検知、Whisper パッケージの選定）を掘り下げる。

---

## 5. 関連ドキュメント

- `docs/research/on_device_stt/recording_segmentation_whisper.md` — 本書の方向Aを具体化した実装手段の調査（録音・VAD・Whisper パッケージ／日本語モデル選定）
- `docs/research/on_device_stt/continuous_listening_limitation.md` — 今回の `speech_to_text` アプローチの限界
- `docs/research/speech_recognition_accuracy.md` — ストリーミング型 vs バッチ型（Whisper）の精度差
- `docs/research/on_device_llm.md` — オンデバイス処理の調査

## 参考リンク

- [whisper_flutter_new | pub.dev](https://pub.dev/documentation/whisper_flutter_new/latest/)
- [whisper_kit | pub.dev](https://pub.dev/packages/whisper_kit)
- [Cheetah Streaming Speech-to-Text — Picovoice Docs](https://picovoice.ai/docs/cheetah/)
- [Running Transcription Models on the Edge — ionio.ai](https://www.ionio.ai/blog/running-transcription-models-on-the-edge-a-practical-guide-for-devices)
- [Best Speech-to-Text APIs in 2026 — Deepgram](https://deepgram.com/learn/best-speech-to-text-apis-2026)
- [Google Cloud Speech-to-Text Pricing](https://cloud.google.com/speech-to-text/pricing)
