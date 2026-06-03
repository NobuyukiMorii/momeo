# OS 組み込みのオンデバイス LLM 調査

## この文書について

- **目的**: OS に組み込まれた LLM（オンデバイス LLM）を開発者が直接呼び出せる仕組みを整理する。音声認識の確定テキストを「整文」する後処理レイヤーの実装候補として検討する。
- **調査日**: 2026-06-01
- **きっかけ**: `speech_recognition_accuracy.md` の施策「LLM 後処理レイヤー」を検討する中で、後処理 LLM には「OS 組み込み（オンデバイス）」と「外部 API」の2ルートがあると分かった。本書は前者を深掘りする。
- **関連文書**: [`speech_recognition_accuracy.md`](./speech_recognition_accuracy.md)

---

## TL;DR（結論サマリ）

- 2026 年現在、**iOS / Android ともに OS 組み込みのオンデバイス LLM を開発者が直接呼べる**ようになっている。
  - **iOS 26+**: Foundation Models framework（Apple Intelligence の ~3B モデル）
  - **Android**: ML Kit GenAI APIs（Gemini Nano / AICore 経由）
- どちらも **要約・整文・校正（proofread / refinement）** を公式ユースケースに掲げており、「確定テキストの整文」用途に向いている。
- **無料・オフライン・端末内完結**で、「OS の進化に乗る」戦略と完全に一致する。
- ただし **(1) 対応端末が新しめの機種に限られる**、**(2) Flutter プラグインがまだ beta 中心**、という2つの現実的な制約がある。非対応端末向けのフォールバック設計が前提になる。

---

## 1. OS 組み込み LLM とは

OS（またはその AI 基盤）に同梱された LLM を、アプリ開発者が API 経由で直接呼び出せる仕組み。クラウドの外部 API と違い、推論が端末内で完結する点が最大の特徴。

- **無料**（OS の機能として提供される）
- **オフラインで動作**
- **データが端末外に出ない**（プライバシー保護）
- **モデルの進化は OS アップデートに乗る**（自前で乗り換え不要）

---

## 2. iOS: Foundation Models framework

### 概要
- **iOS 26 で導入**された、オンデバイス LLM への開発者向けフレームワーク。
- **Apple Intelligence の中核である約30億パラメータ（~3B）のオンデバイスモデル**に、Swift コードから直接アクセスできる。

### 得意分野
公式が挙げるユースケースは、**要約・エンティティ抽出・テキスト理解・refinement（整文）・短い対話・創造的コンテンツ生成**など。**「整文」がまさに公式ユースケースに含まれる**。

### API の特徴
- Swift と密に統合されており、少ない記述でモデルにリクエストできる。
- **Guided generation**（構造化出力）の仕組みがあり、Swift の型に注釈を付けることで、モデル出力を構造化データとして受け取れる。

### 対応条件
- iOS 26 / iPadOS 26 / macOS 26 以降。
- **Apple Intelligence 対応端末**で、かつ **Apple Intelligence が有効**なときに利用可能。
- 補足: Apple は「オンデバイス」と「サーバ」の2種類の foundation model を持つが、本フレームワークから直接使えるのはオンデバイスの ~3B モデル。

---

## 3. Android: ML Kit GenAI APIs（Gemini Nano）

### 概要
- **ML Kit GenAI APIs** が、オンデバイス LLM **Gemini Nano** を使うための高レベルインターフェースを提供する。
- 基盤は **AICore**（オンデバイスで生成 AI 基盤モデルを実行する Android システムサービス）。推論は端末内で完結する。

### 提供される機能
- **Proofreading（校正）**: 短いメッセージの校正
- **Summarization（要約）**: 記事や会話の要約
- **Prompt API**: カスタムプロンプトによるテキスト生成

→ **校正（proofread）** が公式機能として用意されており、整文用途に直結する。

### 対応条件
- **対応端末はフラッグシップ中心**（Pixel 8 以降、Pixel 9 / 10 シリーズ、Honor の一部端末など）。
- システムサービス **AICore のインストール・更新が必要**（Google Play 経由）。
- 今後: Gemini Nano 4 が developer preview 提供中。Prompt API は 2026 年末までにフラッグシップ端末で Gemini Nano 4 対応予定。Structured Output API（構造化出力）や Prefix Caching（推論高速化）も予定されている。

---

## 4. Flutter から使えるか（プラグイン状況）

プラグインは登場しているが、**いずれも比較的新しく beta 段階**で、`speech_to_text` ほど枯れていない。本番採用には実機検証が前提。

| プラグイン | 対象 | 特徴 |
|---|---|---|
| `flutter_local_ai` | iOS Foundation Models + Android ML Kit GenAI + Windows AI | ネイティブ API をラップ。モデルの追加ダウンロード不要。プラットフォーム横断で統合 |
| `foundation_models_framework` | iOS 26+ / macOS | beta。streaming は安定。structured generation / tool calling は開発中 |
| `gemini_nano_android` | Android AICore | オフライン・低レイテンシ。対応端末 + AICore が必要 |
| `ai_edge_sdk` | Google AI Edge SDK（Gemini Nano） | オンデバイス Gemini Nano を Flutter から利用 |

---

## 5. 外部 API との比較

整文の後処理 LLM を「OS 組み込み（オンデバイス）」にするか「外部 API」にするかのトレードオフ。

| 観点 | OS 組み込み LLM（オンデバイス） | 外部 API |
|---|---|---|
| OS の進化に乗れるか | ◎ まさに乗れる | △ 自前で乗り換え |
| コスト | ◎ 無料 | △ 従量課金 |
| オフライン | ◎ 動く | × ネット必須 |
| プライバシー | ◎ 端末内完結 | △ 外部送信 |
| 対応端末 | △ 新しめの端末のみ | ◎ 選ばない |
| 品質 | ○ 整文用途には十分（3B 級） | ◎ 大規模で高品質 |
| Flutter 成熟度 | △ beta 中心 | ◎ 枯れている |

---

## 6. 本アプリへの示唆

- 「確定テキストの整文・句読点付け」程度の**軽い後処理なら、3B 級のオンデバイス LLM で十分実用的**。要約・refinement・proofread は各社がまさに公式ユースケースに掲げている。
- 戦略的には **OS 組み込み LLM（オンデバイス）が第一候補**。「OS に乗る」という方針と一致し、**音声認識(OS) → 整文(OS 組み込み LLM)** で処理を OS 内に閉じられる。
- 実装上の前提となる制約は2つ:
  1. **対応端末の制約** … 非対応端末向けに「整文なし（生の最終結果をそのまま使う）」または「外部 API フォールバック」の二段構えが必要。
  2. **Flutter プラグインが beta** … 実機検証を必須とし、本番採用は慎重に。
- 整文は `listening_flow` の **確定（`onStatus='done'`）を起点に非同期で実行**すると、リアルタイム表示の UX を壊さない。
- 進め方の提言: まず**整文なし（最終結果をそのまま採用）をベースライン**にし、整文は段階的に足す。整文を導入するなら、オンデバイス LLM を第一候補に、フォールバック設計とセットで検討する。

---

## 7. まとめ・提言

- OS 組み込みのオンデバイス LLM は 2026 年に実用段階へ。**iOS = Foundation Models framework**、**Android = ML Kit GenAI（Gemini Nano）**。
- どちらも整文・校正・要約が得意で、**「OS に乗る」戦略と完全に一致**する。音声認識から整文まで OS 内で完結できる。
- 課題は **対応端末の限定** と **Flutter プラグインの成熟度**。フォールバック設計を前提に、段階導入するのが現実的。

---

## 参考リンク

### 一次情報

- [Apple Developer: Foundation Models（公式ドキュメント）](https://developer.apple.com/documentation/FoundationModels)
- [Apple Newsroom: Apple's Foundation Models framework unlocks new intelligent app experiences](https://www.apple.com/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/)
- [Apple Machine Learning Research: Introducing Apple's On-Device and Server Foundation Models](https://machinelearning.apple.com/research/introducing-apple-foundation-models)
- [Google for Developers: Overview of the ML Kit GenAI APIs](https://developers.google.com/ml-kit/genai)
- [Android Developers: Gemini Nano](https://developer.android.com/ai/gemini-nano)

### Flutter プラグイン

- [pub.dev: flutter_local_ai](https://pub.dev/packages/flutter_local_ai)
- [pub.dev: foundation_models_framework](https://pub.dev/packages/foundation_models_framework)
- [pub.dev: gemini_nano_android](https://pub.dev/packages/gemini_nano_android)
