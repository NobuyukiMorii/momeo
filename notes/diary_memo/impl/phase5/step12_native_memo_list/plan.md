# Step 12 ネイティブ一覧を作り、画面を差し替える

## 目的

Flutter のカード一覧をやめ、OS の部品（iOS は `UITextView`、Android は `TextView`）で作った一覧に置き換える。

メモ全件を1つの文書にしておくと、あとの step で、OS 標準の文字選択をメモをまたいで使えるようになる。


| 今                  | 変更後                         |
| ------------------ | --------------------------- |
| メモ1件 = カード1枚（枠あり）  | メモ1件 = ブロック1つ（枠なし、本文だけ）     |
| 日付の区切り・時刻を出す       | 出さない                        |
| 話している間、アクティブカードが出る | 出さない（気配は step 25 で「.」として戻す） |
| カードのタップで選択・長押しでコピー | できない（丸は step 16〜17 で足す）     |


## やること

### 一覧をつくる


| 場所      | 中身                                                           |
| ------- | ------------------------------------------------------------ |
| Dart    | ネイティブ一覧を画面に埋め込む部品。メモ一覧を「文書」にしてネイティブへ渡す                       |
| iOS     | 文書を1つの `UITextView` に並べる。書体はヒラギノ                             |
| Android | 文書を1つの `TextView` に並べ、`ScrollView` でスクロールする。書体は Noto Sans JP |
| 両 OS    | アプリの起動時に、ネイティブ一覧を登録する                                        |


両 OS で、次の見た目をそろえる。

- 古いメモが上、新しいメモが下。メモが少ないうちは画面の下に寄せる
- 本文の文字サイズ 18、行の高さは文字の約2倍、ブロックの間は 24
- 開いたときは一番下（最新）を見せる。一番下を見ている間は、新しいメモが来たらついていく

### 画面を差し替える

- リスニング画面のカード一覧を、ネイティブ一覧に置き換える
- アクティブカードの出し入れ（アニメーションと、その合図を受け取る処理）をやめる

使わなくなったカードの部品や状態は、次の step 13 で消す。

## 参照する `spike/diary-memo` のコード

spike のネイティブ一覧は、あとの step の機能まで入った完成形。この step では、文書を並べて表示するところだけを取り出す。


| ファイル                                                     | 場所                                                                                                              |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `lib/widgets/native_memo_list.dart`                      | 部品と文書の受け渡し（`_viewType`・`_updateMethod`・`_bodyFontSize`、13〜24行目）                                                 |
|                                                          | 部品の本体（47〜266行目）のうち、ネイティブ View の生成・文書の組み立て・送信                                                                    |
| `ios/Runner/NativeMemoList.swift`                        | Dart とのやり取りの定数 `ChannelMethod`・`DefaultValue`（12〜29行目）のうち `update` と本文の分 |
|                                                          | 本文の定数 `BodyLayout`（34〜55行目）                                                                                     |
|                                                          | 登録用の `NativeMemoListFactory`（91〜108行目）                                                                          |
|                                                          | Dart とのやり取り `NativeMemoList`（140〜179行目）                                                                         |
|                                                          | 本文 `MemoDocumentView` のうち、`update`（268行目〜）・`buildDocument`（355行目〜）・`layoutSubviews`・`layoutDocument`（526〜559行目） |
|                                                          | 色と書体 `opaqueColor`・`bodyFont`（341〜353行目）                |
| `android/app/src/main/kotlin/jp/momeo/NativeMemoList.kt` | 定数（50〜89行目）のうち、`update` と本文の分                          |
|                                                          | 登録用の `NativeMemoListFactory`（136〜145行目）                                                                         |
|                                                          | Dart とのやり取り `NativeMemoList`（180〜223行目）                                                                         |
|                                                          | 本文 `MemoDocumentView` のうち、`update`（332行目〜）・`buildDocumentText`（398行目〜）・行の高さの span（570〜613行目）                    |
|                                                          | 文字の大きさと色 `applyTextSizeAndColor`（409〜417行目）             |
|                                                          | スクロール `MemoScrollView`（831行目〜）のうち、下寄せと最新へのスクロール                                                                 |
|                                                          | 行の高さ `MemoLineHeightSpan`・`MemoBlockSpans`（1030〜1049行目） |
| `ios/Runner/AppDelegate.swift`                           | 一覧の登録（17〜21行目）                                                                                                  |
| `ios/Runner.xcodeproj/project.pbxproj`                   | `NativeMemoList.swift` をビルド対象に足す4か所                                                                             |
| `android/app/src/main/kotlin/jp/momeo/MainActivity.kt`   | 一覧の登録（16〜20行目）                                                                                                  |
| `lib/pages/listening/listening_page.dart`                | 一覧の組み立て `_buildMemoList`（188〜220行目）と、`build` の中の一覧（331行目〜）                                                      |


Android で Noto Sans JP を使うのは spike に無い、main で新しく足すもの（step 2 で同梱した書体を使う）。