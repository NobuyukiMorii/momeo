# Step 18 文字を選べるようにする

## 目的

本文の文字を、OS 標準の操作で選べるようにする。

長押しで語を選び、つまみを動かして範囲を広げ、メニューからコピーできる。メモをまたいで選ぶこともできる。


| 操作         | 誰が扱うか   |
| ---------- | ------- |
| 長押し・ダブルタップで語を選ぶ | OS      |
| つまみ・選択色・拡大表示 | OS      |
| メニュー（コピーなど） | OS      |
| 選択範囲を本文の中に収める | アプリ     |


## やること

- iOS：本文を選べるようにする（`isSelectable`）
- iOS：メニューの文言が端末の言語（日本語・英語）に従うよう、アプリの対応言語を宣言する（`Info.plist`）
- Android：本文を選べるようにする（`setTextIsSelectable`）。つまみ・メニューが正しい見た目で出るよう、OS 標準のテーマを当てる
- 両 OS：選択範囲の両端を、掛かっているメモの本文の端までに収める（ブロック間の余白や、本文が空のメモだけを選んだ状態にしない）
- 両 OS：本文に1文字も掛からない選択になったら、選択を畳む

この step では、選んでいる間に録音で一覧が変わると、選択は外れてしまう。それを保つのは step 19。メニューの「コピー」「すべて選択」を整えるのは step 20。

## 参照する `spike/diary-memo` のコード


| ファイル                                                     | 場所                                                       |
| -------------------------------------------------------- | -------------------------------------------------------- |
| `ios/Runner/Info.plist`                                  | `CFBundleLocalizations`（9〜13行目）                          |
| `ios/Runner/NativeMemoList.swift`                        | 本文を選べるようにする（`init` の `isSelectable`、239行目）               |
|                                                          | 選択の対象になるメモ `copyableBlocks`（259〜262行目）                    |
|                                                          | 選択が変わったとき `textViewDidChangeSelection`（450〜472行目）のうち、両端を収めるところ |
|                                                          | 選択を畳む `collapseSelectionLater`（474〜487行目）                  |
| `android/app/src/main/kotlin/jp/momeo/NativeMemoList.kt` | OS 標準のテーマ `themedContext`（182〜184行目）                     |
|                                                          | 本文を選べるようにする（`init` の `setTextIsSelectable`、302行目）        |
|                                                          | 選択の対象になるメモ `copyableBlocks`・`copyableBlocksIn`（321〜326行目）  |
|                                                          | 選択が変わったとき `onSelectionChanged`・`fitSelectionToBlocks`・`collapseSelectionLater`（499〜537行目） |

