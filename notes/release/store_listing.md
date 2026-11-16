# ストア掲載文（英語）

App Store と Google Play に載せる文章。軸はサイト（docs/index.html）と同じ 2 つ。

- **Write with your voice**：声で書くメモ。開けばすぐ聞いていて、話したことが文章になる
- **No one else hears it.**：声もメモも端末の外に出ない

書くときの決まり：

- 仕組みの言葉（on-device、local など）より、使う人の不安と使う場面の言葉で書く
- 機能は実際の動きと一致させる。特に「開いている間だけ聞く」「アカウント不要」「端末の外に出ない」は、プライバシーポリシーと Data safety の回答（store_submission/submission_notes.md）と食い違わせない
- 文字数は各ストアの上限に収める（下の表の数は数えた値）
- どの国のストアにも、この英語の文章をそのまま載せる（日本語版は作らない）
- スクリーンショットは画面そのまま載せる（キャプション付きの画像にはしない）

---

## App Store

| 項目 | 上限 | 文字数 |
|---|---|---|
| App Name | 30 | 5 |
| Subtitle | 30 | 21 |
| Promotional Text | 170 | 142 |
| Keywords | 100 | 96 |
| Description | 4000 | 1018 |

### App Name

```
momeo
```

### Subtitle

```
Write with your voice
```

### Promotional Text

```
Open it and start talking. What you say turns into text, line after line, and stays on your phone. No account, no cloud. No one else hears it.
```

### Keywords

```
voice notes,dictation,speech to text,transcribe,journal,diary,memo,private,offline,thoughts,talk
```

### Description

```
Write with your voice.

momeo is a notebook you write by talking. Open the app and start talking. There is no record button and no typing. What you say turns into text, line after line, like a page in a notebook.

Say whatever is on your mind:
• Something to do before Wednesday
• A gift idea for someone's birthday
• How the meeting really went
• A plan for the weekend
• What to pick up on the way home

NO ONE ELSE HEARS IT
Speech recognition runs on your phone. Your voice and your notes never leave it. No account, no cloud, no ads, no tracking. Not even we can read them.

momeo only listens while it is open on your screen. Close it, and it stops.

MADE FOR THINKING OUT LOUD
• Starts listening the moment you open it
• Your notes flow as one continuous page, newest at the bottom
• Tap anywhere to fix a word. It edits like any notepad
• Select and copy what you need

REQUIREMENTS
iOS 26 or later. momeo uses your device's language. The first time, your iPhone may download the speech model for that language.
```

---

## Google Play

| 項目 | 上限 | 文字数 |
|---|---|---|
| App name | 30 | 28 |
| Short description | 80 | 70 |
| Full description | 4000 | 1074 |

### App name

```
momeo: Write with your voice
```

### Short description

```
Open it and talk. Your words become notes that never leave your phone.
```

### Full description

```
Write with your voice.

momeo is a notebook you write by talking. Open the app and start talking. There is no record button and no typing. What you say turns into text, line after line, like a page in a notebook.

Say whatever is on your mind:
• Something to do before Wednesday
• A gift idea for someone's birthday
• How the meeting really went
• A plan for the weekend
• What to pick up on the way home

NO ONE ELSE HEARS IT
Speech recognition runs on your phone. Your voice and your notes never leave it. No account, no cloud, no ads, no tracking. Not even we can read them.

momeo only listens while it is open on your screen. Close it, and it stops.

MADE FOR THINKING OUT LOUD
• Starts listening the moment you open it
• Your notes flow as one continuous page, newest at the bottom
• Tap anywhere to fix a word. It edits like any notepad
• Select and copy what you need

REQUIREMENTS
Android 13 or later, with on-device speech recognition for your language. momeo uses your device's language. The first time, your phone may download the speech model for that language.
```

---

## スクリーンショット

撮影の仕組みは `notes/release/screenshots/README.md`。並び順と見せたいことは次のとおり。

| # | ファイル | 画面 | 伝えたいこと |
|---|---|---|---|
| 1 | `01_listening_idle.png` | 何も書いていない、聞いている画面 | 開いたらもう聞いている（ボタンが無い） |
| 2 | `02_listening_first_memo.png` | 1 つ話して、次を話している途中（「.」） | 話すと文章になる |
| 3 | `03_listening_growing_memos.png` | 3 つ目まで | 思いついた順に書き足されていく |
| 4 | `04_listening_many_memos.png` | 5 つ目まで | 長い文もそのまま文章になる |
| 5 | `05_listening_memo_list.png` | 7 つ並んだページ（話していない） | 1 日の考えが 1 枚のページになる |

メモの中身は、サイトの画面の再現（docs/demo.js）と同じ独り言の台本の冒頭。
