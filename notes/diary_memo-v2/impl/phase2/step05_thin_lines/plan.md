# Step 5 線とつまみを細くする

## 目的

縦線・横線・スクロールつまみを、背景の波線と同じ太さにそろえる。


| もの | 今 | この step の後 |
| --- | --- | --- |
| 縦線・横線 | 1.5 | 0.5 |
| つまみの横棒 | 1.5 | 0.5 |


つまみの色（本文の色）と、掴める広さは変えない。

## やること

- 縦線・横線とつまみの太さを 0.5 にする（背景の日付の高さ合わせに使う Dart の値も）

## 参照する `spike/diary-memo-v2` のコード


| ファイル | 場所 |
| --- | --- |
| `lib/pages/listening/listening_page.dart` | `_thumbThickness`（20行目） |
| `ios/Runner/NativeMemoList.swift` | `RailLayout.lineWidth`（64行目）、`ScrollThumbLayout.thickness`（75行目） |
| `android/app/src/main/kotlin/jp/momeo/NativeMemoList.kt` | `RAIL_WIDTH_DP`（117行目）、`THUMB_THICKNESS_DP`（128行目） |
