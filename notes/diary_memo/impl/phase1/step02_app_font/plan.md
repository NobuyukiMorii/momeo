# Step 2 書体をそろえる（iOS はヒラギノ、Android は Noto Sans JP）

## 目的

1つの文の中で、日本語と英数字の書体が混ざらないようにする。

## やること


| OS      | 変更                                  |
| ------- | ----------------------------------- |
| iOS     | 端末に入っている `Hiragino Sans` を使う        |
| Android | `Noto Sans JP`（標準の太さと太字）をアプリに同梱して使う |


## 参照する `spike/diary-memo` のコード


| ファイル                                  | 場所                                                |
| ------------------------------------- | ------------------------------------------------- |
| `lib/foundation/app_text_styles.dart` | `appFontFamily`（3〜5行目）と各スタイルの `fontFamily`        |
| `pubspec.yaml`                        | `fonts:`（書体の同梱の書き方。spike は Dancing Script で使っている） |


Noto Sans JP は spike に無い、main で新しく足すもの。