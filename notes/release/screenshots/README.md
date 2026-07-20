# ストア掲載用スクリーンショットの撮影の仕組み

このディレクトリの PNG は、手で操作して撮ったものではなく、
「スクリーンショット撮影モード」でアプリを起動して自動撮影したもの。
この文書は、その仕組みを初見でも追えるように説明する。

## まず結論だけ

- アプリには「撮影モード」という隠し起動方法がある。ビルド時に
  `SCREENSHOT_SCENE=シーン名` という文字列を埋め込むと、通常の起動フローを
  すべてスキップして、指定シーンの固定データだけを画面に表示する
- シェルスクリプトは、シーンごとに「ビルド → シミュレータに入れる → 起動 →
  スクリーンショット保存」を繰り返しているだけ
- 画面そのもの（カードのデザイン、波線、レイアウト）は本物のコードを
  そのまま使っている。**偽物なのは「表示するデータ」だけ**

## 全体の流れ

```
scripts/take_ios_screenshots.sh（Android 版も同じ構造）
  │
  │ ① シーンごとにループ:
  │    flutter build ios --simulator --dart-define=SCREENSHOT_SCENE=listening_idle
  │                                   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  │                                   「listening_idle という文字列を埋め込んでビルドしろ」
  ▼
lib/main.dart
  │ ② 起動時に埋め込まれた文字列を読む:
  │    const screenshotSceneName = String.fromEnvironment('SCREENSHOT_SCENE');
  │    - 通常ビルド → 空文字 → いつも通り MyApp を起動（撮影モードのコードは無関係）
  │    - 撮影ビルド → 'listening_idle' → ScreenshotApp を起動
  ▼
lib/pages/dev/screenshot/screenshot_app.dart
  │ ③ シーン名からシーン定義（固定データ）を引き、
  │    「本物のリスニング画面」を「偽物の状態」で表示する
  ▼
lib/pages/listening/listening_page.dart（本物の画面。撮影用の変更は一切なし）
  ▲
  │ ④ スクリプトが数秒待ってからシミュレータのスクショコマンドを実行
  │    （iOS: xcrun simctl io screenshot / Android: adb screencap）
  └─ このディレクトリに PNG が保存される
```

## 登場ファイルと役割

| ファイル | 役割 |
|---|---|
| `scripts/take_ios_screenshots.sh` | iOS の一括撮影。シミュレータ起動・ステータスバー整形（9:41、満充電）・ビルド・撮影 |
| `scripts/take_android_screenshots.sh` | Android 版。エミュレータ起動・デモモードで時計を 9:41 に・ビルド・撮影 |
| `lib/main.dart` | 起動の分岐点。埋め込み文字列が入っていたら撮影モードへ（追加された分岐は10行だけ） |
| `lib/pages/dev/screenshot/screenshot_scenes.dart` | **7シーンの「台本」**。各シーンで見せるメモの文言・時刻・発話中かどうかの固定データ |
| `lib/pages/dev/screenshot/screenshot_app.dart` | 撮影モードの本体。シーンの台本どおりに画面を表示する |

## 鍵になる仕組みは2つだけ

### 鍵①: `--dart-define` = ビルド時に文字列を焼き込むスイッチ

`flutter build --dart-define=SCREENSHOT_SCENE=listening_idle` とすると、
Dart コード側の `String.fromEnvironment('SCREENSHOT_SCENE')` が
`'listening_idle'` という**コンパイル時定数**になる。実行時の環境変数ではなく、
アプリバイナリに焼き込まれる値、という点がポイント。

- 何も指定せず普通にビルドすれば空文字になるので、`main()` の分岐は
  必ず通常起動側を通る。**リリースビルドの挙動には一切影響しない**
- 「デバッグメニューから撮影モードに入る」方式にしなかったのは、
  製品コードに撮影用の入り口を残さないため

### 鍵②: Riverpod の override = 画面はそのまま、データの供給元だけ差し替える

このアプリのリスニング画面は「`listeningProvider` が持つ状態を watch して
描くだけの View」として作られている（`listening_page.dart` 冒頭のコメント参照）。
状態を作る側（マイク録音 → VAD → 文字化のパイプライン）と、
描く側（画面）が最初から分離されている。

撮影モードはこの分離を利用して、`ProviderScope(overrides: [...])` で
`listeningProvider` の中身を**固定データを返すだけの偽物 Notifier** に差し替える。

```dart
ProviderScope(
  overrides: [
    listeningProvider.overrideWith(() => _ScreenshotListeningNotifier(scene)),
  ],
  child: MaterialApp(home: ListeningPage()),  // ← 画面は本物
)
```

偽物 Notifier がやることは2つだけ。

- `build()` でシーンの固定メモ一覧を返す（録音パイプラインは起動しない）
- 背景の波線が毎フレーム読みにくる音量値として、正弦波を合成した
  「発話らしい揺れ」を返す（マイクの代わり）

だからマイク権限も STT モデルも不要で、シミュレータだけで撮影できる。
スプラッシュの3シーンはもっと単純で、本物と同じレイアウト部品
（`IntroSettingLayout`）に文字を静止表示しているだけ。

## 7シーンの一覧（ストアに並べる順）

台本の実体は `screenshot_scenes.dart`。文言・時刻を変えたらスクリプトを再実行するだけ。

| ファイル名 | シーン名 | 内容 |
|---|---|---|
| `01_splash_auto_start` | `splash_auto_start` | スプラッシュ「Auto-start」 |
| `02_splash_auto_stop` | `splash_auto_stop` | スプラッシュ「Auto-stop」 |
| `03_splash_open_speak_saved` | `splash_open_speak_saved` | スプラッシュ「Open. Speak. Saved.」 |
| `04_listening_idle` | `listening_idle` | 波線だけの静かなリスニング画面 |
| `05_listening_first_memo` | `listening_first_memo` | 発話中ドット＋確定1枚 |
| `06_listening_growing_memos` | `listening_growing_memos` | 発話を重ねて確定3枚＋発話中 |
| `07_listening_memo_list` | `listening_memo_list` | 時刻付きの確定一覧5枚（発話なし） |

シーン名は「対象画面＋状態」で付けてあり、表示する文言には依存しない。
デモメモは差し替え可能な例文で、現在は「朝、今日の計画を声に出して
立てている」という設定の5件（7:41〜7:45）。7:42 の2件で「同じ分の
カードは日時を1つにまとめる」という実際の表示ルールが写るようにしてある。

## 撮り直し方

```bash
# iOS（iPhone 16 Pro Max シミュレータ。App Store 必須の 6.9 インチ = 1320x2868）
bash scripts/take_ios_screenshots.sh

# Android（Pixel エミュレータ。1080x2424）
bash scripts/take_android_screenshots.sh
```

シーンごとにビルドし直すため、全7シーンで数分〜十数分かかる。
撮影時のハマりどころ（スクショ保存先は絶対パス必須、実機接続中の adb の
対象指定、Android debug ビルドの起動待ちなど）への対処は、
各スクリプトのコメントに理由つきで書いてある。

## 保守の方針

この一式は申請・ストア更新のときにしか使わないため、積極的には保守しない。

- 本体のリファクタでコンパイルが壊れたら、そのとき最小限直す
  （壊れる場所はコンパイラが指してくれる。画面は本物を使っているので、
  UI の変更には自動で追従する）
- 大きな作り直しで邪魔になったら消してよい。撮影ノウハウはスクリプトの
  コメントとこの文書、git 履歴に残る
