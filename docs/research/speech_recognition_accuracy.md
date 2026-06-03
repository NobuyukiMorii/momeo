# 音声認識の精度に関する調査

## この文書について

- **目的**: `speech_to_text`（OS 標準の音声認識を呼び出すパッケージ）で感じる「精度の低さ」の原因を切り分け、**OS を使う方針を維持したまま**精度を上げる方法を整理する。
- **調査日**: 2026-06-01
- **対象**: `speech_to_text` 7.4.0（iOS = `SFSpeechRecognizer` / Android = `SpeechRecognizer` をラップするパッケージ）
- **きっかけ**: 実機で試すと、ChatGPT などの音声入力に比べて認識精度が低く感じる。これは「OS の限界」なのか「実装の問題」なのか、それとも「他サービスが特別なことをしている」のかを知りたい。

---

## TL;DR（結論サマリ）

精度が低く感じるのは、次の **3つの要因が重なっている**ためで、「OS の限界」だけが理由ではない。

1. **OS の音声認識は「リアルタイム・ストリーミング型」** … 仕組み上、精度が犠牲になる
2. **ChatGPT は「録音まるごと一括処理型（Whisper）」** … そもそも別パラダイムで有利
3. **ChatGPT はおそらく認識後に LLM で文章を整えている** … 「文脈で直している」という直感は当たっている

そして重要な点として、**OS を使う方針のままでも精度を上げる余地は大きい**。特に「**確定は最終結果を使う**（コスト0）」と「**確定後に LLM 後処理を1枚かませる**（最大のレバー）」の2つが効く。

---

## 1. 問題意識

体感として、OS 標準の音声認識（`speech_to_text` 経由）の精度が、ChatGPT などの普段使っている音声入力より低く感じる。原因として次の切り分けをしたい。

- **(A)** OS の音声認識エンジン自体の限界なのか
- **(B)** 今の実装方法（パッケージの使い方・オプション設定）に改善余地があるのか
- **(C)** 他サービスが文脈補正など特別な処理をしているのか

また方針として、**「OS の音声認識を使う」という方向性は維持したい**。理由は、OS 自体が進化し続けるため、長期的にはサードパーティ製エンジンが OS に勝てなくなると考えられるから。その前提で「OS を使いながら精度を高める方法」を探る。

---

## 2. 精度が低く感じる 3つの要因

### 要因A: ストリーミング型の宿命（影響が最も大きい）

iOS の `SFSpeechRecognizer` も Android の `SpeechRecognizer` も、**話している最中に逐次テキストを出す「ストリーミング型」**である。

ストリーミング型は「**未来の音声を先読みできない**」まま、その瞬間までの音だけで単語を確定しようとする。文の後半を聞けば前半の解釈を直せるのに、それを待たずに確定してしまうため精度が落ちる。

> バッチ型 ASR（Whisper など）は発話全体を待ってから処理し、双方向の文脈で高精度を出す。一方ストリーミング ASR は話しながら逐次出力するため、先読みできない分だけ精度が落ちる。

### 要因B: 「途中経過テキスト」が最も不正確（実装上、特に重要）

`speech_to_text` の公式説明によると、認識器は音声を受け取るほど結果を**書き換える**ため、**最終結果（`isFinal = true`）は最後の途中経過（partial result）と異なることがある**。

つまり、画面でリアルタイムに更新されていくテキストは「**確定前の推測**」であり、最も精度が低い状態。**最終結果のほうが精度が高い**。リアルタイムに変化していくテキストを見て精度を判断すると、一番不利な見方になってしまう。

### 要因C: モデルそのものの規模差

OS のオンデバイス／標準モデルは、ChatGPT が使う Whisper のような巨大モデル（約 68 万時間の音声で学習）と比べると小さく、語彙・頑健性（アクセントやノイズ耐性）で劣る。これは純粋に「モデルの地力」の差。

---

## 3. ChatGPT との差の「正体」

「文脈で判断して直しているのか？」という推測について、答えは **「半分そう、でも本質はもっと根本的」**。

| 観点 | OS 音声認識（今の実装） | ChatGPT 音声入力 |
|---|---|---|
| 認識方式 | リアルタイム・ストリーミング | **録音まるごと一括（バッチ）** |
| 文脈の利用 | 過去の音だけ | **発話全体の前後文脈** |
| 使用モデル | OS 標準（比較的小さい） | **Whisper（巨大・高頑健）** |
| 仕上げ | なし（生の認識結果） | **おそらく LLM で整文・句読点付け** |

ポイントは、**ChatGPT はそもそもリアルタイムでやっていない**こと。話し終わるまで録音をため、**全部聞いてから**一気に変換するので、後半の文脈で前半を直せる。「速さ」を捨てて「精度」を取った設計と言える。

加えて、ASR の生出力を **LLM で後処理して誤り・句読点を直す**手法は研究でも実証されており、文字誤り率を **9〜21% 程度削減**できるという報告がある。ChatGPT の「自然な仕上がり」は、この後処理が効いている可能性が高い。

---

## 4. OS を使いながら精度を上げる方法（効果が大きい順）

「OS の方向で行きたい」という戦略は妥当。その前提で、効果が大きい順に施策を挙げる。

### ① 確定テキストは「最終結果」を使う（実装の見直し・コスト0）

カードに確定保存する文字列は、途中経過ではなく **`isFinal = true` の最終結果**にする。これだけで体感精度が上がる。途中経過は「話している実感を出すための表示用」と割り切る。

- 現在の `listening_flow.md` の方針（部分結果は表示用、`onStatus='done'` で確定）と整合する。
- 確定時に「**最後の partial ではなく final を採用する**」点を仕様として明記しておくとよい。

### ② iOS はサーバ認識のまま使う（すでにそうなっている）

`speech_to_text` は `onDevice` のデフォルトが `false` で、iOS では **Apple サーバ側の高精度モデル**を使う。オンデバイス強制（`onDevice = true`）にすると精度が落ちるので、**精度重視なら現状（サーバ）が正解**。

- プライバシー要件やオフライン対応が必要になったら、初めて精度とのトレードオフを検討する。
- サーバ認識には「1セッションあたりの時間制限」があるため、`listenFor` での上限設定とセッション再開の設計は引き続き必要。

### ③ LLM 後処理レイヤーを足す（最大のレバー）

**OS で認識 → 確定テキストを LLM に通して整文する**ハイブリッド構成。これが「ChatGPT っぽい仕上がり」に最も近づく現実的な方法。

- OS の進化の恩恵はそのまま受けられる（戦略を維持できる）。
- リアルタイム表示は OS、確定後の品質は LLM、と役割分担できる。
- 本アプリの「カード確定（`done`）」のタイミングと相性がよい。確定した瞬間に裏で整文をかければ、リアルタイム表示の UX を壊さない。
- **注意**: 精度の高い文に余計な修正を入れて改悪するリスクがあるため、「明らかな誤りだけ直す／勝手に意味を変えない」とプロンプトで制約するのが定石。

### ④ iOS 26 の新フレームワーク `SpeechAnalyzer`（将来の選択肢）

iOS 26 には `SpeechAnalyzer` / `SpeechTranscriber` が登場している。**Whisper Large v3 Turbo の約2倍速**・ノイズ耐性向上という強みがある。

- ただし**カスタム語彙（`contextualStrings`）が使えず**、その点では旧 `SFSpeechRecognizer` のほうが精度が高い場面もある、という評価。
- `speech_to_text` パッケージがまだ対応していない可能性が高いので、**今すぐ採用ではなく「OS 進化に乗る」観測対象**として位置づける。

### ⑤ 固有名詞対策（`contextualStrings` / カスタム語彙）

人名・専門用語・製品名などを事前登録して認識を寄せる機能（iOS の `contextualStrings`）は精度に効く。

- ただし **`speech_to_text` パッケージは基本これを公開していない**ため、現状は使いにくい。
- 必要になったら、ネイティブ実装やパッケージ乗り換えの検討材料になる。多くのケースは ③ の LLM 後処理でカバーできる。

---

## 5. 本アプリ（listening_flow）への示唆

- **確定テキストは final を採用する**（施策①）。`listening_flow.md` に「確定時は最後の partial ではなく最終結果を使う」と明記する余地がある。
- **エラーハンドリングは精度問題とは別軸**だが関連する。iOS の `error_no_match` はセッション終端で頻繁に出る無害なノイズで、致命扱いしない。`permanent` フラグは信頼しない（別途の実機調査結果より）。
- **LLM 後処理（施策③）は、確定（`done`）イベントを起点に非同期で実行する**設計が UX と相性がよい。将来の機能拡張ポイントとして有力。
- OS を使う方針自体は維持してよい。精度向上は「実装の見直し（①②）」＋「後処理の追加（③）」で段階的に進められる。

---

## 6. まとめ・提言

- **OS を使う方針はそのままで OK。** 戦略的に正しい。
- 体感精度が低い主因は **(a) ストリーミング型の宿命** と **(b) 途中経過テキストを見ていること**。まず**確定は最終結果を使う**だけで改善する（コスト0）。
- ChatGPT との差は「文脈補正」だけでなく **「バッチ処理 + 巨大モデル + LLM 後処理」** という別パラダイム。完全に同じにはできないが、**確定後に LLM 整文を1枚かませる**のが、OS 方針を保ったまま最も近づける手。
- iOS 26 の `SpeechAnalyzer` は「OS の進化に乗る」具体的な観測ポイントとして記録しておく。

---

## 参考リンク

### 一次情報

- [Apple Developer: requiresOnDeviceRecognition（オンデバイス認識の指定）](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)
- [Apple Developer (WWDC25): Bring advanced speech-to-text to your app with SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)
- [OpenAI: Introducing Whisper（学習データ規模・頑健性）](https://openai.com/index/whisper/)
- [arXiv: Adapting Whisper for Streaming Speech Recognition via Two-Pass Decoding（ストリーミング vs バッチの精度差）](https://arxiv.org/html/2506.12154v1)
- [arXiv: A Three-Stage LLM-Based Framework for ASR Error Correction（LLM 後処理による誤り率削減）](https://arxiv.org/pdf/2505.24347)
- [pub.dev: speech_to_text（onDevice / partialResults / 最終結果の挙動）](https://pub.dev/packages/speech_to_text)

### 二次情報（解説記事）

- [Apple's New Speech Framework: SpeechAnalyzer vs SFSpeechRecognizer](https://blakecrosley.com/blog/speech-framework-vs-sfspeechrecognizer)
- [iOS Speech Recognition in 2026: The Complete Guide (Picovoice)](https://picovoice.ai/blog/ios-speech-recognition/)
- [Android Speech Recognition in 2026: The Complete Guide (Picovoice)](https://picovoice.ai/blog/android-speech-recognition/)
- [Does ChatGPT Voice Features Use Whisper (UMA Technology)](https://umatechnology.org/does-chatgpt-voice-features-use-whisper/)
