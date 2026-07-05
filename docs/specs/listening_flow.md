# リスニングフロー仕様

## 概要
権限許可後、アプリは自動的にリスニング状態で開始されます。ユーザーは録音ボタンを探すことなく話し始めることができます。

音声認識はオンデバイス STT（`sherpa_onnx` + NeMo CTC）で行います。OS の音声認識サービス（`speech_to_text` パッケージ）は廃止しました。モデルが端末にあれば実行は完全オフラインです。

> リスニング画面に入る前提として、文字化エンジンの準備完了を待つ「準備ゲート」があります（`docs/specs/preparation_gate.md`）。リスニング画面に到達した時点でエンジンは常に使用可能です。

## 画面構成

1. **現在リスニング中のカード (アクティブ)**
   - リスニング中であることを示すインジケーターを表示します。日時は非表示です。
   - 認識途中のテキスト（部分結果）は表示しません。新方式は発話終了後に一括で文字化するため、部分結果がそもそも存在しません。
2. **確定済みメモカード**
   - インジケーターを非表示にし、右下に作成日時を表示します。長押しでテキストコピーが可能です。

## 認識パイプライン

リスニング画面に入ると、録音 → 区切り → 文字化のパイプライン（`lib/stt/stt_listening_pipeline.dart`）が自動で開始されます。

```text
🎤 record でマイクを連続キャプチャ（PCM16 / 16kHz / モノラル）
  ↓ Float32 に変換し、512サンプル窓ごとに供給
sherpa 内蔵 Silero VAD（発話の開始〜終了を検出）
  ↓ 1発話ぶんの音声チャンク
sherpa-onnx OfflineRecognizer（NeMo CTC）でバッチ文字化
  ↓
確定テキスト → メモとして保存・表示
```

- 文字化エンジンはアプリ全体で1つだけ保持される共有エンジン（`sttEngineProvider`）を借りて使います。
- 画面を離れるときはパイプラインを停止し、VAD 内に残った末尾の発話を押し出して文字化してから破棄します。

## メモ確定条件

**VAD の発話終了検出を確定トリガーとする。**

Silero VAD の区切り設定（`stt_listening_pipeline.dart` の定数）:

| 項目 | 値 | 意味 |
|---|---|---|
| `minSilenceDuration` | 1.5秒 | 無音がこの時間続いたら発話終了とみなす（旧仕様 `pauseFor` と同じ値。担い手が VAD に変わった） |
| `minSpeechDuration` | 0.25秒 | これより短い音は発話とみなさない |
| `maxSpeechDuration` | 30秒 | 1発話の上限。超えたら強制的に区切る（旧仕様 `listenFor` に相当） |

## 確定テキストの採用ルール

- 確定テキストは、発話チャンク全体を一括で文字化した結果をそのまま採用します。旧方式のような「部分結果と最終結果の使い分け」は存在しません。
- **空文字は保存しない**: 無音・雑音による空の認識結果は、保存前に弾きます（前後の空白を除去した上で空なら破棄）。

## 確定フロー

```text
ユーザーが話す
↓
【 確定条件 】
 └─ 無音が 1.5秒 続き、VAD が発話終了を検出する
↓
1発話ぶんの音声チャンクを sherpa-onnx（NeMo CTC）で文字化する（実測 100〜300ms）
↓
確定テキストをメモとして保存し、「確定済みメモカード」として一覧の先頭に表示する
↓
録音は止まらず連続キャプチャのまま、次の発話を待ち受ける
```

旧方式と異なり、発話が確定するたびに認識セッションを再開する必要はありません。録音は画面にいる間ずっと連続しています。

## 今後の検証項目

- 無音 1.5秒 の区切りが実際の利用感として心地よいかどうかは、実機検証を通じて調整します。
- 転写中（100〜300ms・メインスレッド）に喋った音声を取りこぼさないかを実機で計測します（`docs/on_device_stt/outline.md` 末尾「実機確認時の宿題」参照）。

## 参照する既存デザインドキュメント

- docs/design/03_screen_states/details/ListeningInitial.md
- docs/design/03_screen_states/details/ListeningFirstItem.md
- docs/design/03_screen_states/details/ListeningSecondItem.md
- docs/design/03_screen_states/details/ListeningThirdItem.md
- docs/design/03_screen_states/details/ListeningManyItemsOverview.md

## 関連ドキュメント

- 実装計画・採用経緯: `docs/on_device_stt/outline.md`
- モデルの配布方式: `docs/on_device_stt/model_distribution.md`
- 権限フロー（マイクのみ）: `docs/specs/permission_flow.md`

## 一次情報・参考リンク

- [sherpa-onnx documentation](https://k2-fsa.github.io/sherpa/onnx/index.html)
- [Silero VAD (GitHub)](https://github.com/snakers4/silero-vad)
- [record (pub.dev)](https://pub.dev/packages/record)
