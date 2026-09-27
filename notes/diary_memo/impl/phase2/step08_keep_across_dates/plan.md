# Step 8 日付が変わっても同じメモに書き足す

## 目的

夜中の0時をまたいで話し続けても、話が2つのメモに割れないようにする。


| 今               | 変更後          |
| --------------- | ------------ |
| 日付が変わったら新しいメモにする | 同じメモに書き足す |


## やること

日付の変わり目で区切る判定（`_isSameDay`）をやめる

## 参照する `spike/diary-memo` のコード


| ファイル                                     | 場所                                      |
| ---------------------------------------- | --------------------------------------- |
| `lib/providers/listening_providers.dart` | `_shouldEndCurrentBlock` の最後の判定（434〜435行目） |


spike の関数名は `_shouldEndCurrentBlock`。main では step 14 まで `_shouldEndCurrentCard` のまま。
