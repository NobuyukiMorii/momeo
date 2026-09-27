# Step 13 使わなくなったカード関連を消す

## 目的

step 12 でカード一覧をやめたので、カードのためだけにあった部品・状態を片付ける。

見た目と動きは変わらない。

## やること

### ファイルごと消す


| 消すもの                  | 場所                                                               |
| --------------------- | ---------------------------------------------------------------- |
| ボイスカード                | `lib/widgets/voice_card.dart`                                    |
| カード右上の声のアイコン          | `lib/widgets/voice_icon.dart`                                    |
| 日付の区切り                | `lib/widgets/date_separator.dart`                                |
| カードに出す日時を決める処理        | `lib/pages/listening/memo_card_view_data.dart`                   |
| カタログの VoiceCard の見本    | `lib/pages/dev/catalog/sections/widgets/widgets_voice_card_section.dart` |
| カタログの VoiceIcon の見本    | `lib/pages/dev/catalog/sections/widgets/widgets_voice_icon_section.dart` |


### 一部を消す


| 消すもの                                        | 場所                                        |
| ------------------------------------------- | ----------------------------------------- |
| カタログの目次から、上の2つの見本                           | `lib/pages/dev/catalog/catalog_page.dart` |
| アクティブカードに時刻を出すための状態 `speechStartedAt`       | `lib/providers/listening_providers.dart`  |
| アクティブカードを引っ込める合図 `emptyResultCount`         | `lib/providers/listening_providers.dart`  |
| ページに残ったカード用の定数・状態・import（時刻の書式、コピーの知らせなど） | `lib/pages/listening/listening_page.dart` |
| アニメーションが選択バーの1つだけになるので、`TickerProviderStateMixin` を `SingleTickerProviderStateMixin` にする | `lib/pages/listening/listening_page.dart` |
| 冒頭の説明の「アクティブカードのアニメーションに翻訳する」 | `lib/providers/listening_providers.dart` |


- メモの作成日時に使う `_speechStartedAt`（Notifier の中の値）は残す
- 空の結果を受け取る `withEmptyResult` は残す（step 25 で、話し中の「.」を消す合図に使う）

## 参照する `spike/diary-memo` のコード

spike は消したあとの形になっている。


| ファイル                                      | 場所                                          |
| ----------------------------------------- | ------------------------------------------- |
| `lib/providers/listening_providers.dart`  | `ListeningState`（45〜168行目）に2つの状態が無い            |
| `lib/pages/dev/catalog/catalog_page.dart` | `Widgets` の目次（49〜53行目）に VoiceCard・VoiceIcon が無い |
| `lib/pages/listening/listening_page.dart` | 冒頭の import と定数（1〜31行目）、状態（43〜81行目）             |

