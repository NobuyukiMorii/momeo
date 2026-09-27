# Step 23 スクロール中だけ背景に日付を出す

## 目的

ブロックごとの日付は出していないので、さかのぼっているときに「いつのメモか」が分かるようにする。

スクロールしている間だけ、つまみの高さにあるメモの日付を、本文の後ろに薄く大きく出す。

```text
 お婆ちゃんの家に行った。元気そうで   ◯
      2026.09.26                     ─┼─  ← つまみ
 耳と記憶は弱くなってて心配。         ◯
```


| 項目       | 動き                                              |
| -------- | ----------------------------------------------- |
| 出す日付     | つまみの高さより上で、一番近い丸を持つメモが始まった日（時刻は出さない）              |
| 出すとき     | 指やつまみでスクロールしている間だけ。止まって 0.6秒たつと消える               |
| 出さないとき   | 新しいメモが増えて、一番下へ自動で移るとき                            |
| 現れ方・消え方  | 0.2秒かけてふわっと                                     |
| 見た目      | 筆記体（Dancing Script）、文字サイズ 48、本文の色の 10%           |
| 置く場所     | 高さはつまみにそろえる。左右は本文の表示領域の中央。狭い画面では縮めて1行に収める       |
| 触ったとき    | 反応しない（下の本文に届く）                                   |


## やること

- 書体 Dancing Script をアプリに同梱する（`assets/fonts/` と `pubspec.yaml`）
- Dart：背景に日付を描く部品を作る
- iOS・Android：つまみの高さと、その高さにあるメモの id を Dart へ知らせる。指やつまみで動かしたのか、アプリが動かしたのかも一緒に知らせる
- Dart：知らせを受けて日付を出し、止まってしばらくしたら消す（画面全体を組み直さず、日付の層だけを動かす）

## 参照する `spike/diary-memo` のコード


| ファイル                                                     | 場所                                                     |
| -------------------------------------------------------- | ------------------------------------------------------ |
| `assets/fonts/DancingScript-Regular.ttf`                 | ファイルごと                                                 |
| `pubspec.yaml`                                           | `fonts:` の Dancing Script（89〜93行目）                      |
| `lib/widgets/listening_memo_date_backdrop.dart`          | ファイルごと                                                 |
| `lib/widgets/native_memo_list.dart`                      | `_thumbMethod`（21行目）、`MemoListThumb`（29〜31行目）、受け取り（148〜154行目） |
| `lib/pages/listening/listening_page.dart`                | 定数（24〜31行目）、状態（57〜66行目）と後片付け（95〜97行目）                   |
|                                                          | `_onThumbChanged`・`_buildThumbDate`（243〜283行目）、置くところ（326〜329行目） |
| `ios/Runner/NativeMemoList.swift`                        | Dart への知らせ（155〜157行目、164行目）                           |
|                                                          | 知らせる値の状態（187〜189行目、220〜223行目）                         |
|                                                          | `reportThumb`・`setContentOffsetByApp`（568〜591行目）         |
|                                                          | 高さにあるメモ `blockWithCircleAbove`（627〜631行目）               |
| `android/app/src/main/kotlin/jp/momeo/NativeMemoList.kt` | Dart への知らせ（194〜196行目、202行目）                           |
|                                                          | 高さにあるメモ `blockIdAt`・`latestBlockCircle`（670〜677行目）      |
|                                                          | 知らせる値の状態（843〜852行目）                                  |
|                                                          | `onScrollChanged`・`reportThumb`・`scrollToByApp`（930〜963行目） |


`pubspec.yaml` の `fonts:` には、step 2 で Noto Sans JP を足している。Dancing Script はその並びに足す。
