# Step 26 開発用の画面を合わせ、使っていないファイルを消す

## 目的

アプリの動きに関わらない、開発用のコードの残りを片付ける。

見た目と動きは変わらない。

## やること


| 変更                              | 中身                                          |
| ------------------------------- | ------------------------------------------- |
| `lib/pages/dev/screenshot/screenshot_scenes.dart` | コメントだけ直す。「アクティブカード」を「『.』が出ている」「発話中」にする       |
| `lib/pages/dev/recording/recording_scenes.dart`   | ファイルごと消す（どこからも使われていない）                      |
| `test/widget_test.dart`                         | ファイルごと消す（Flutter の雛形のカウンターのテストが残っていたもの） |


## 参照する `spike/diary-memo` のコード


| ファイル                                            | 場所                          |
| ----------------------------------------------- | --------------------------- |
| `lib/pages/dev/screenshot/screenshot_scenes.dart` | `speechActive` のコメント（20行目） |
|                                                 | 各シーンのコメント（56・65・74・83行目）   |


`recording_scenes.dart` と `test/widget_test.dart` は、spike には無い（消した後の形）。
