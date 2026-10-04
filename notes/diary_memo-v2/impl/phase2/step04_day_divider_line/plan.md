# Step 4 丸を日付の区切り線に変える

## 目的

メモごとの丸をなくし、日付が変わるところにだけ、画面の端から端まで横線を引く。


| 項目 | 今 | この step の後 |
| --- | --- | --- |
| 丸 | メモごとに1つ | 無い |
| 縦線 | 丸と丸の間 | 一番上のメモから下まで、1本 |
| 横線 | 無い | その日の最初のメモの上（一番上のメモには引かない） |


```text
 耳と記憶は弱くなってて心配。         │
──────────────────────────────────────┼──  ← 日付の区切り
 京都水族館に行ってソフトクリーム     │
```

横線の色と太さは縦線と同じ。

## やること

- 各メモが「その日の最初のメモ」かを Dart で決め、文書に入れて渡す
- 丸を消し、横線を引く（iOS は線を描く View を画面幅に広げる）
- 「丸」と呼んでいた位置を「区切り」と呼び変える

## 参照する `spike/diary-memo-v2` のコード


| ファイル | 場所 |
| --- | --- |
| `lib/widgets/native_memo_list.dart` | 文書の `startsDay`（170・180〜185行目） |
| `ios/Runner/NativeMemoList.swift` | `startsDay`（116・342行目）、`layoutRail`（644行目〜）、`layoutBoundaries`（654行目〜）、`drawRail`（756行目〜） |
| `android/app/src/main/kotlin/jp/momeo/NativeMemoList.kt` | `startsDay`（168・439行目）、`boundaryYs`（675行目〜）、`drawRail`（807行目〜） |
