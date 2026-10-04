# Step 7 つまみと文字選択を見分ける

## 目的

つまみの上でも、指の動かし方で、つまみのドラッグと文字選択を見分ける。


| つまみの上での操作 | 結果 |
| --- | --- |
| 指を置いてすぐ動かす | つまみのドラッグ |
| 長押し・ダブルタップ | 文字選択 |
| 動かさずにすぐ離す | 本文の1回タップ（文字選択中なら選択を外す） |


文字選択の端（OS のつまみ）がつまみと重なったときは、文字選択の端を掴む。

## やること

- iOS：つまみのドラッグを本文の View に付け直し、縦線の View はタッチを受け取らないようにする（step 1 で足した途中の形をやめる）
- Android：長押しになる前に指が動いたときだけ、つまみのドラッグとして奪う

## 参照する `spike/diary-memo-v2` のコード


| ファイル | 場所 |
| --- | --- |
| `ios/Runner/NativeMemoList.swift` | ドラッグを付ける（253行目）、`selectionEdgeContains`（452行目〜）、`selectionEdgeTouchMargin`（80行目）、`MemoRailView`（849行目）、`MemoScrollThumbPan`（864行目〜） |
| `android/app/src/main/kotlin/jp/momeo/NativeMemoList.kt` | `longPressTimeout`（842行目）、`onInterceptTouchEvent`（986行目〜） |
