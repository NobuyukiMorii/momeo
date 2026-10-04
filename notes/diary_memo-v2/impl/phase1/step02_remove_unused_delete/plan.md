# Step 2 使わなくなった削除のしくみを消す

## 目的

step 1 で選択バーが無くなり、使われなくなったメモの削除のしくみと部品を片付ける。

見た目と動きは変わらない。

## やること

- メモをまとめて消す処理（`deleteMemos`・`withMemosRemoved`・`deleteByIds`）を消す
- 選択バーでしか使っていなかった部品（`pressable_scale.dart`）を消す

## 参照する `spike/diary-memo-v2` のコード

spike は消したあとの形になっている。


| ファイル | 場所 |
| --- | --- |
| `lib/repositories/voice_memo_repository.dart` | `delete` と `deleteAll` の間（44〜51行目）に `deleteByIds` が無い |
| `lib/providers/listening_providers.dart` | `ListeningState`（141行目〜）と Notifier（542行目〜） |


spike のこの場所には、step 8 で足す文字の削除（`withTextDeleted`・`deleteTextRanges`）が入っている。この step では足さない。
