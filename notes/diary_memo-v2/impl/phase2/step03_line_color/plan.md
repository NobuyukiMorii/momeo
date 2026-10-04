# Step 3 線と日付の色をそろえる

## 目的

背景の波線・右の縦線と丸・背景の日付を、同じ薄いグレー `#CFD1D4` にそろえる。透明度は使わない。


| もの | 今 | この step の後 |
| --- | --- | --- |
| 背景の波線 | 本文の色の 20% | `#CFD1D4` |
| 縦線と丸 | 本文の色 | `#CFD1D4` |
| 背景の日付 | 本文の色の 10% | `#CFD1D4`（今より一段濃い） |


波線の見た目はほぼ変わらない（本文の色の 20% を白に重ねた色が `#CFD1D4`）。

## やること

- 色 `#CFD1D4` を足し、`AppColors.onSurfaceFaint` と名付ける
- 波線・日付をこの色にする
- 縦線と丸の色を Dart から渡し、この色で描く

## 参照する `spike/diary-memo-v2` のコード


| ファイル | 場所 |
| --- | --- |
| `lib/foundation/app_palette.dart` | `gray300`（7・18行目） |
| `lib/foundation/app_colors.dart` | `onSurfaceFaint`（13・46行目） |
| `lib/widgets/listening_backdrop.dart` | 波線の色（140行目） |
| `lib/widgets/listening_memo_date_backdrop.dart` | 日付の色（32行目） |
| `lib/widgets/native_memo_list.dart` | 文書の `railColor`（193行目） |
| `ios/Runner/NativeMemoList.swift` | 既定値（28行目）、受け取り（299行目）、`drawRail` の線の色（762行目） |
| `android/app/src/main/kotlin/jp/momeo/NativeMemoList.kt` | 既定値（69行目）、受け取り（396行目）、`railPaint` の色（459行目） |


spike の `drawRail` は step 4 で書き直した後の形。この step では丸の色も同じ色にする。
