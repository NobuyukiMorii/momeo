# Step 12: 待ち画面のステータス表示（スプラッシュ風）

## ひとことで言うと

待ち画面（`PreparationGatePage`）は、スプラッシュと同じ「**中央の1行テキストが流れていく**」デザイン。
いま何をしているかは短い英語ひとことで、DLの進み具合は "Downloading 37%" の**数字**で伝える。
処理が進行中のフェーズは**末尾のドットが動き続け**、画面が固まって見えないようにする。
**進捗バーは置かない**。

---

## デザインの方針

お手本は `lib/pages/splash_page.dart`。

- 部品はスプラッシュと同じ: `IntroSettingLayout` ＋ `AppTextStyles.headline` の中央1行テキストのみ。
- フェーズが進んだら、スライド演出（今のテキストが左へ退場、次が右から登場）で切り替わる。
- 進捗バーを置かない理由: 起動体験を「短い言葉が流れていく」で統一しており、バーだけが異物になるため。進捗は数値が増えることで十分伝わる。

---

## 文言（確定）

| フェーズ | いつ | 表示 |
|---|---|---|
| DL開始待ち | Android 初回、DLがまだ始まる前 | **Getting ready** ＋ドット |
| DL中 | Android 初回 | **Downloading 37%**（数字だけその場で更新） |
| メモリに読み込み中 | 準備が間に合わなかったとき | **Almost there** ＋ドット |
| 失敗 → 自動再試行中 | 失敗直後 | **Retrying** ＋ドット |
| 再試行が続けて失敗 | 連続5回失敗したとき | **Try restarting**（表示後も裏で再試行は続ける） |

- トーンはスプラッシュの `'Open. Speak. Saved.'` に合わせる: **短い言い切り。説明文は付けない**。
- 処理が進行中のフェーズ（Getting ready / Almost there / Retrying）は、静止画に見えないよう末尾にドットを足して動かす（`Getting ready` → `Getting ready .` → `..` → `...` → ドットなしに戻る、の繰り返し）。ドットは文言の一部ではなく「動いていること」を示す演出。
- "Downloading" は数字の増加で動きが伝わるため、"Try restarting" はユーザーへの依頼（処理中ではない）のため、ドットは付けない。
- 完了時の文言は無い（完了したら画面ごとリスニングへ遷移するため）。
- "Retrying" と "Try restarting" の発動条件・切り替えは自動再試行側で実装する（`step13_auto_retry.md`）。ここは文言の定義だけ。

Android 初回の流れの例:

```
Getting ready → Downloading 0% … 100% → Almost there → （リスニングへ遷移）
```

---

## 実装の骨子

- スプラッシュの `AnimatedTextSequence` は「1.5秒ごとに次へ」の**時間駆動**、待ち画面は「状態が変わったら次へ」の**状態駆動**。スライド演出の描画部分だけを `TextSlideTransition`（Widget を受け取る）として共有し、その上に状態駆動版の `ContentSlideSwitcher` を置く（スプラッシュの見た目・挙動は不変）。
- 役割は3層に分ける: `PreparationGatePage` は「いまどのフェーズか」を決めるだけ（`_resolvePhase`）。フェーズの中身（文言・ドット・DL%）は**フェーズごとの小さなウィジェットが自己完結で描く**（`_buildPhaseContent`）。`ContentSlideSwitcher` はフェーズが変わった時に中身をスライドで入れ替えるだけ。
- ドットは共通ウィジェット `ActivityDotsText` が内部タイマーで回す。DL% は `DownloadingProgressText` が「Downloading n%」を組み立て直すだけで、フェーズが同じ間はスライドが起きない（毎%スライドさせるとチカチカするため）。数字は等幅数字（tabular figures）にして、% の位置が数字の変化で揺れないようにする。
- 「DL中」と「読み込み中」は、エンジン（`sttEngineProvider`）から見るとどちらも「準備中」。DL進捗（`sttModelDownloadStateProvider`）を併読して出し分ける。

---

## 完了の目安

- Android 初回（bundletool の模擬配信）で、Getting ready → Downloading n% → Almost there と流れてリスニングへ繋がる。
- DL% の数字がなめらかに増え、スライド演出はフェーズ切替時だけ起きる。
- Getting ready / Almost there / Retrying の末尾でドットが増減し続け、静止して見えない。
- 待ち画面の見た目がスプラッシュと揃っている。スプラッシュ側の見た目・挙動は変わっていない。
- `flutter analyze` が通る。

---

## 作業チェックリスト

- [x] `AnimatedTextSequence` からスライド演出の描画部分を `TextSlideTransition` に切り出す（スプラッシュの挙動は変えない）
- [x] 状態駆動版の `PhaseSlideText` を作る（テキストの変化でスライドを起動）
- [x] DL進捗を画面から読む配線（`sttModelDownloadStateProvider`）を足す
- [x] フェーズ別文言を出し分ける（"Try restarting" の発動は自動再試行側で実装）
- [x] DL% は数字だけその場更新、スライドはフェーズ切替時のみ
- [x] `flutter analyze` が通る

ドット演出の追加時に、上記の構成を次の形に作り替えた。

- [x] `TextSlideTransition` を文字列ベースから Widget ベースにする（スプラッシュは `Text` を渡すだけで挙動不変）
- [x] `PhaseSlideText` を `ContentSlideSwitcher`（contentKey ＋ child）に作り替え、「その場更新」の特例分岐をなくす
- [x] ドット演出の `ActivityDotsText` を作り、Getting ready / Almost there / Retrying に適用する
- [x] `flutter analyze` が通る
