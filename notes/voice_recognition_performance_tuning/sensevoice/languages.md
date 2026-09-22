# 日本語・英語・中国語で使うとき

調査日: 2026-09-22。[入口](README.md)

## 1. 言語ごとに期待値を分ける

公式論文の代表的な結果を抜粋します。値は誤り率で、低いほどよいものです。日本語・中国語は CER、英語は WER なので、言語をまたいで数値を直接順位づけしません。

| Common Voice | SenseVoice Small | Whisper small | Whisper large-v3 |
|---|---:|---:|---:|
| 日本語 CER | 11.96 | 19.51 | 10.34 |
| 英語 WER | 14.71 | 14.85 | 9.39 |
| 中国語 zh-CN CER | 10.78 | 19.60 | 12.55 |

出典: [FunAudioLLM 論文 v2 Table 6][paper]。これは論文のモデル・データ・正規化による値です。**採用した int8 ONNX の実機精度や、本人の口語・英語混じりの精度ではありません。** 「全言語で Whisper large と同等」という読み方はできません。

## 2. <a id="language"></a>自動判定と固定指定

### momeo は auto を基準にする

[S6](../spike/sensevoice.md) では同じ固定音声に `auto` と `ja` を適用し、日本語の利得がなく、普通話は `ja` で崩れました。採用時に自動判定を選んだ理由は今も有効です。

一方、公式 FunASR の回答には、日本語と分かっている入力への `ja` 指定が案内されています。これは選択肢の説明であり、momeo の実測を覆す比較結果ではありません。[公式 Discussion #1735][ja-discussion]

言語指定は入力の埋め込みを変える方式で、指定外の言語の文字をすべて禁止する仕組みではありません。`ja` を「漢字や英字の出方を好みに固定するスイッチ」と扱わないほうがよいです。[公式モデル実装][model]

**再比較するなら**、日本語なのに言語ラベルが別言語になる短文、英語だけの短文など、言語判定を疑う具体例に絞ります。`auto / ja / en / zh` の全組合せを常時実行する案は、推論回数と選択ロジックを増やすため、最初の手にはしません。

### 中国語の利用者報告から分かる限界

| 報告 | 確認できること | 言えないこと |
|---|---|---|
| [SenseVoice #130][issue130]、2024-09-23 | 投稿者は中国語が日本語になるケースを報告 | すべての中国語でautoが不適切、とは言えない |
| [SenseVoice #169][issue169]、2024-12-16 | 指定言語と異なる広東語が出るとの報告 | 原因・一般的な修正方法は確定できない |

日英中を自由に話す momeo では、常時の日本語固定より、失敗例で `lang` を確認できる実験ログの方が原因を絞りやすいと考えます。これは調査からの提案です。

## 3. 日本語中の英語と固有名詞

**英語だけの発話を認識できることと、日本語文中の英語を希望する綴りで出すことは別の課題です。**

momeo では、英語がカタカナになる点を受容して採用済みです。ただし `ITリテラシー → アイティイテラス`、`airdrop → エアジョロ` は、カタカナか英字かという好みだけでなく、語自体の誤認も含みます。[採用判断](../decision/adopt-sensevoice.md)

比較時には次を分けます。

| 種類 | 例 | 調整の方向 |
|---|---|---|
| 許容する表記差 | AirDrop / エアドロップ | 表記の好みとして扱い、意味の誤りと分ける |
| 音の誤認 | エアジョロ | 入力範囲、ITN、モデル側を調べる |
| 語の脱落 | 発話冒頭の英単語が消える | まず元音声に語頭が入っているか確認 |
| 固有名詞の綴り | 人名、製品名、社名 | 必要な語に限定した辞書・追加学習を将来検討 |

標準の sherpa 1.13.8 SenseVoice には、hotword を渡すだけで直す経路がありません。第三者の [streaming-sensevoice][streaming] や [CTC hotword fork][hotword-fork] は、デコーダ等を追加した別実装です。日本語の改善実証や現行Dartへの互換性は確認できていません。

認識後の置換辞書は、安定して同じ誤表記が出る語には候補になりますが、消えた音を復元できません。[既存の辞書検討](../spike/notation-dict.md) では材料が少なく見送っています。新しい失敗例が溜まったときに見直す位置づけです。

## 4. <a id="spaces"></a>日本語の不自然な空白

既存例は `それ に比較して、徳川 家康だっ たりとか。`。現行アプリは内部の空白を変更していません。

sherpa の [SymbolTable][symbol] は SentencePiece 系の `▁` を空白に変換し、[SenseVoiceの結果変換][impl] はtokenを連結します。**日本語内部の空白がそのまま残る経路は確認できますが、この例のどのtokenが原因かは未確認**です。また、FunASR の rich postprocess が日本語内部空白を解消するとの保証も確認できませんでした。

特に実用上は、現在の [検索処理](../../../lib/pages/listening/memo_keyword_filter.dart) で `徳川 家康` が `徳川家康` に一致しないことが問題になります。

改善候補は2つあり、別々に試せます。

- **検索用だけ正規化する**: 表示・保存文を保ち、本文と検索語の日本語文字間の空白に寛容な照合を追加する。既存の空白で区切る複数キーワードの意味は維持する。
- **保存前に表示用整形をする**: 日本語文字同士の空白など、対象を限定して除去する。採用するなら既存方針に合わせて保存前に適用し、表示済みカードをあとから書き換えない。

最初は検索だけの比較が小さく済みます。空白をすべて削ると `machine learning`、英文、型番などを壊すため、`徳川 家康` だけで成功判定せず、英語・日英境界・数字も反例として見る必要があります。漢字同士の空白も常に不要とは限りません。

日本語アプリの一次実装記録として、[AviUtl2-WhisperAutoSub][aviutl] は日本語文字の間の空白だけを除去する変更を記載しています。ただし複数ASRを扱うアプリの設計例であり、SenseVoice固有の不具合修正の証明ではありません。

## 5. 数字・助数詞・言い直し

既存の `1600年 → 16002年` に対して、**歴史的に正しい年へ自動修正する、余分な数字を機械的に削る、といった対処は根拠がありません。** 元音声・区間・ITN条件を使って切り分けます。

[FunASR #2417][itn-issue]（2025-03-10）には、中国語で数字を反復したところ、ITN後に連結した数字になるという利用者報告があります。数字の反復や言い直しを試す動機にはなりますが、日本語の既存例と同じ原因とは断定できません。

| 分類 | 比較に含めたい発話例（今回の新規実測ではない） | 見たいこと |
|---|---|---|
| 年号 | 千六百年 | 値と「年」の境界 |
| 言い直し | 千六百二年、違う、千六百年 | 訂正前後を混ぜて一つの数にしないか |
| 日付・時刻 | 九月二十二日、午後三時半 | 区切りと助数詞 |
| 金額・小数 | 一万二千円、三点一四 | 桁・小数点 |
| 一桁ずつの数 | ゼロ、九、ゼロ、… | 連結が望ましい用途と反復を区別 |
| 固有名詞 | 一橋、四谷 | 数値化してはいけない語 |

ITN OFF のほうが音声内容を保っても、メモとしての読みやすさが下がる可能性があります。正解の文字列、数値、読みやすさの3つを分けます。外部の日本語 ITN や句読点モデルを追加するなら、サイズ・遅延・多言語への影響を伴う別施策です。

## 6. 各言語のアプリから拾える使い方

以下は開発者自身のREADMEに書かれた設計です。比較実験で優位性が示された「普遍的な推奨値」ではありません。

| 一次資料 | 実装・運用上の工夫 | momeo に持ち帰れる点 |
|---|---|---|
| [Realtime Translator][translator] | sherpa + Silero + SenseVoiceをmacOS/iOS/browserで利用。途中表示と確定を区別 | 連続入力を扱うUIと、モデルが非ストリーミングであることを両立できる |
| [funasr-subtitle][subtitle] | 英語で句読点だけに依存せず休止を使う字幕分割。小数・略語を考慮 | 句点が出たら即カード分割、という設計は別途評価が必要 |
| [Obsidian realtime transcription][obsidian] | ローカルSenseVoiceの用語補正を保守的な認識後処理として説明 | 「用語辞書」が音声デコードに効くのか、出力置換なのかを区別する |

普通話中心の使い方で有効なピンインによる同音補正を、日本語のかな・漢字変換へそのまま移せるとは考えません。言語別の補正は、日英中が混在したときの副作用も含めて比較します。

[paper]: https://arxiv.org/html/2407.04051v2
[ja-discussion]: https://github.com/modelscope/FunASR/discussions/1735
[model]: https://github.com/QwenAudio/SenseVoice/blob/ea15219509625e5d4c5143c37c86970135886b5d/model.py
[issue130]: https://github.com/QwenAudio/SenseVoice/issues/130
[issue169]: https://github.com/QwenAudio/SenseVoice/issues/169
[streaming]: https://github.com/pengzhendong/streaming-sensevoice
[hotword-fork]: https://github.com/wsweishu/sherpa-onnx-sensevoice-hotword/blob/main/README_SENSEVOICE_CTC_HOTWORD.zh-CN.md
[symbol]: https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/symbol-table.cc
[impl]: https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/offline-recognizer-sense-voice-impl.h
[aviutl]: https://github.com/nkopikaso/AviUtl2-WhisperAutoSub/blob/main/README.md
[itn-issue]: https://github.com/modelscope/FunASR/issues/2417
[translator]: https://github.com/baijunjie/realtime-translator
[subtitle]: https://github.com/rockbenben/funasr-subtitle
[obsidian]: https://github.com/garetneda-gif/obsidian-realtime-transcription
