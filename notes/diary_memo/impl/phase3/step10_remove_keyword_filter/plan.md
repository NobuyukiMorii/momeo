# Step 10 検索の絞り込みを消す（しくみ）

## 目的

step 9 で検索フィールドが無くなり、使われなくなった「検索語で一覧を絞り込むしくみ」を片付ける。

見た目と動きは変わらない。

## やること


| 消すもの                   | 場所                                             |
| ---------------------- | ---------------------------------------------- |
| 検索語で絞り込む処理             | `lib/pages/listening/memo_keyword_filter.dart`（ファイルごと） |
| 検索語（`_keywords`）と、それで絞った一覧 | `lib/pages/listening/listening_page.dart`      |
| 絞り込みで隠れたメモの打ち出しを取り消す処理（`_cancelHiddenTypeIn`） | `lib/pages/listening/listening_page.dart` |
| 検索中はアクティブカードを出さない条件    | `lib/pages/listening/listening_page.dart`      |


## 参照する `spike/diary-memo` のコード

spike には絞り込みが無い。一覧に渡すメモの形として見る。


| ファイル                                      | 場所                                      |
| ----------------------------------------- | --------------------------------------- |
| `lib/pages/listening/listening_page.dart` | `build` の冒頭（286〜299行目）。`listening.memos` を絞り込まずにそのまま使う |

