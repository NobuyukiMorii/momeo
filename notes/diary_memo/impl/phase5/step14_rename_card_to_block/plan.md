# Step 14 「カード」を「ブロック」に呼び変える

## 目的

一覧はもうカードではないので、コードの名前とコメントを今の形に合わせる。

呼び名が変わるだけで、見た目と動きは変わらない。

## やること

メモ一覧の「カード」を指している名前とコメントを、「ブロック」（またはメモ）にする。


| 今                        | 変更後                       |
| ------------------------ | ------------------------- |
| `withCurrentCardEnded`   | `withCurrentBlockEnded`   |
| `_stopRecordingAndEndCard` | `_stopRecordingAndEndBlock` |
| `_shouldEndCurrentCard`  | `_shouldEndCurrentBlock`  |
| `_endCurrentCard`        | `_endCurrentBlock`        |
| コメントの「カード」「新カード」         | 「ブロック」「新ブロック」             |


対象のファイル

- `lib/providers/listening_providers.dart`（名前とコメントのほとんど）
- `lib/pages/dev/recording/recording_listening_simulator.dart`（`withCurrentCardEnded` の呼び出し）
- `lib/pages/listening/listening_page.dart`・`lib/widgets/listening_backdrop.dart`・`lib/widgets/listening_selection_bar.dart`（コメント）

### 変えないもの

- 録音設定パネルの「選択肢カード」（メモ一覧とは別の部品）
- 開発用カタログの STT のカード（`_ModelDownloadCard` など）

## 参照する `spike/diary-memo` のコード


| ファイル                                                        | 場所                                          |
| ----------------------------------------------------------- | ------------------------------------------- |
| `lib/providers/listening_providers.dart`                    | `withCurrentBlockEnded`（116〜126行目）         |
|                                                             | `_stopRecordingAndEndBlock`（369〜377行目）      |
|                                                             | `_shouldEndCurrentBlock`・`_endCurrentBlock`（416〜454行目） |
|                                                             | 確定テキストの受け取り〜追記（457〜520行目）のコメント              |
| `lib/pages/dev/recording/recording_listening_simulator.dart` | `_finishSpeaking`（96〜99行目）                  |
| `lib/widgets/listening_backdrop.dart`                       | 冒頭の説明（12行目）                                |
| `lib/widgets/listening_selection_bar.dart`                  | ボタンの縮み具合のコメント（82行目）                        |

