# Step 8 選んだ文字を削除する

## 目的

文字選択のメニューに「削除」を足し、選んだ文字をメモから消せるようにする。

- 並びは「コピー」「削除」「すべて選択」。文言は端末の言語に合わせる（削除 / Delete）
- 確認は出さない。元に戻す手段は持たない
- 空白や改行だけが残ったメモは、メモごと消す（余白も詰まる）
- 書き足し先のメモが消えたら、次の発話は新しいメモにする

iOS 15 以前は、OS の仕組み上「削除」が「すべて選択」の後ろに並ぶ。

## やること

- iOS・Android：メニューに「削除」を足し、消す範囲（メモと、本文の中の位置）を Dart へ知らせる
- Dart：本文を書き換えて保存し、空になったメモは消す

## 参照する `spike/diary-memo-v2` のコード


| ファイル | 場所 |
| --- | --- |
| `lib/widgets/native_memo_list.dart` | `MemoTextRange`（34行目）、受け取り（153行目〜） |
| `lib/pages/listening/listening_page.dart` | `_onDeleteText`（85〜86行目） |
| `lib/providers/listening_providers.dart` | `withTextDeleted`（141行目〜）、`deleteTextRanges`（542行目〜） |
| `ios/Runner/NativeMemoList.swift` | iOS 15 以前のメニュー（255〜257行目）、`selectedPieces`（508行目〜）、削除（524行目〜）、iOS 16 以降のメニュー（539行目〜） |
| `android/app/src/main/kotlin/jp/momeo/NativeMemoList.kt` | メニュー（104〜107・329行目〜）、`SelectedPiece`（188行目〜）、`selectedPieces`・削除（595〜620行目） |
