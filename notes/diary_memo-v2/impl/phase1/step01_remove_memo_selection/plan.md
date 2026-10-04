# Step 1 選択バーとメモの選択をなくす

## 目的

縦線・丸のタップでメモを選び、画面下端の選択バーで削除・コピーする機能をなくす。


| 項目 | 今 | この step の後 |
| --- | --- | --- |
| 縦線・丸のタップ | メモの選択が切り替わり、選択バーが出る | 本文の文字選択の操作として扱う |
| 選択中の見た目 | 本文が太字、丸が大きく、線が太い | 無い（いつも同じ） |
| 一覧の右端（右から 40） | 文字選択を始められない | つまみの上を除き、文字選択ができる |


丸は残す（丸をなくすのは step 4）。

## やること

- 選択バーを消す
- 丸のタップでメモを選ぶ機能と、選択中の見た目を消す
- 一覧の右端でも文字を選べるようにする

`deleteMemos` は step 2、仕様書は step 9 で直す。

## 参照する `spike/diary-memo-v2` のコード

spike は消したあとの形になっている。このあとの step の変更も入っているので、選択に関わる部分だけを見る。


| ファイル | 場所 |
| --- | --- |
| `lib/pages/listening/listening_page.dart` | `_ListeningPageState`（32行目〜）、`_buildMemoList`（62〜71行目） |
| `lib/widgets/native_memo_list.dart` | 引数（53〜57行目）、受け取り（146行目〜）、文書（178行目） |
| `ios/Runner/NativeMemoList.swift` | 書体（54行目・354〜355行目）、`MemoBlock`（109行目〜）、つまみを掴める幅（77行目） |
| `android/app/src/main/kotlin/jp/momeo/NativeMemoList.kt` | 書体（97行目）、`MemoBlock`（161行目〜）、行高の span（279行目・633行目〜）、`selectionContains`（535〜537行目）、`onTouchEvent`（825行目） |


iOS の右端は、spike の最終形ではつまみのドラッグを本文の View に付け直して実現している（step 7）。この step では途中の形として、縦線の View がつまみの上だけタッチを受け取るようにする。
