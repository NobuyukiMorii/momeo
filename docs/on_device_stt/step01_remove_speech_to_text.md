# Step 1: speech_to_text 関連の撤去

## この文書について

- **位置づけ**: `outline.md` の「Step 1: speech_to_text 関連の撤去」を、実コードを調査したうえで具体的な作業手順に落とし込んだもの。
- **対応コミット**: 1 step = 1 commit。本ステップは「もう使わない `speech_to_text` の実装・依存・固有設定を取り除く」ことだけを目的とする。
- **調査前提**: `outline.md` の記載を鵜呑みにせず、`speech_to_text` / `SpeechRecognition` 系の参照をリポジトリ全体で grep し、実際の参照箇所と突き合わせた。その結果、**outline.md に書かれていない撤去対象が1つ見つかった**（後述 §3-A）。

---

## 1. このステップの境界（Step 2 との切り分け）

`speech_to_text` 関連の参照は大きく2系統あり、本ステップで扱うのは **(A) パッケージ本体に紐づくもの** のみ。**(B) 音声認識「権限」に紐づくもの** は `outline.md` の方針どおり **Step 2 に回す**。

| 系統 | 内容 | 担当ステップ |
|---|---|---|
| (A) パッケージ本体 | `speech_to_text` 依存・dev catalog の観察セクション・Android の認識サービス検出用 intent | **Step 1（本ステップ）** |
| (B) 音声認識権限 | `Permission.speech`、`NSSpeechRecognitionUsageDescription`、iOS Podfile の `PERMISSION_SPEECH_RECOGNIZER`、権限画面の表示定義 | Step 2 |

> 備考: `outline.md` Step 1 の備考にも「権限の `Permission.speech` は Step 2 で扱う」と明記されている。本ステップでは権限まわりには触れない。

---

## 2. 撤去対象（outline.md に記載済みのもの）

| # | 対象ファイル | 作業内容 | 現状の参照箇所 |
|---|---|---|---|
| 1 | `pubspec.yaml` | `speech_to_text: ^7.4.0` の1行を削除 | L40 |
| 2 | `lib/pages/dev/catalog/sections/packages/packages_speech_to_text_section.dart` | ファイルごと削除 | ファイル全体（観察用セクション） |
| 3 | `lib/pages/dev/catalog/catalog_page.dart` | 上記セクションの import と登録を削除 | import: L12 / 登録: L49 |
| 4 | 未使用 import の確認 | 撤去後に取り残された import がないか確認 | — |

### 補足: #3 を消すと「Packages」カテゴリが空になる問題（要判断）

`catalog_page.dart` の `Packages` カテゴリには現在 `speech_to_text` アイテムしか登録されていない（L48-50）。L49 を消すと **`Packages` カテゴリは items 空になる**。

`catalog_page.dart` は空セクションを「ヘッダーだけ表示して中身は `SizedBox.shrink()`」とする実装（L89-90）になっているため、**消した直後は「Packages という見出しだけが残り、中身が空」**という見た目になる。

判断（本計画での既定）:
- **`Packages` カテゴリの定義（`_Section(title: 'Packages', ...)`）ごと削除する**。
- 理由: `outline.md` では今後 dev catalog に VAD / モデル配置 / 文字化などの**恒久的な検証セクション**を追加していく方針（Step 4・5・6）。それらが追加されるタイミングでカテゴリを作り直せばよく、Step 1 時点で空見出しを残す意味がない。
- ※ もし「Packages カテゴリは将来も使うので見出しは残したい」という意図があれば、L49 の1行だけ消して空カテゴリを残す選択もある。実装前に確認しておきたい論点。

---

## 3. outline.md に**記載がなかった**撤去対象（重要 / 抜け漏れ）

### 3-A. Android マニフェストの「音声認識サービス検出用」intent

`android/app/src/main/AndroidManifest.xml` L45-48 に、`speech_to_text` のための `<queries>` エントリが存在する。

```xml
<!-- speech_to_text: Android 11+ で音声認識サービスを検出するために必要 -->
<intent>
    <action android:name="android.speech.RecognitionService"/>
</intent>
```

- これは **`speech_to_text` パッケージが Android 11+ で端末の音声認識サービスを照会するために必要だった宣言**であり、コメントにも「speech_to_text」と明記されている。**パッケージ本体に紐づく (A) 系統**なので、本ステップで撤去すべき。
- `outline.md` Step 1 にはこの項目がなく、Step 3 の「Android マニフェストに必要な権限宣言（マイク等）を整える」は**追加**の話なのでカバーされない。**outline の抜け漏れとして本ステップに含める。**
- 削除対象は L45-48 の該当 intent ブロックのみ。直上の `PROCESS_TEXT` intent（L41-44）は Flutter エンジンが使う別物なので**残す**。

---

## 4. 本ステップでは**触れないもの**（誤って巻き込まない）

調査で `speech` 文字列にヒットしたが、Step 1 の対象外として明示的に除外するもの。

| 対象 | 内容 | 扱い |
|---|---|---|
| `lib/pages/permissions/permission_page.dart` L26-38 | `Permission.speech` の表示定義（title/button） | **Step 2** |
| `lib/pages/permissions/permission_flow_page.dart` L31 | iOS の権限リストに `Permission.speech` を含む | **Step 2** |
| `ios/Runner/Info.plist` L31-32 | `NSSpeechRecognitionUsageDescription` | **Step 2** |
| `ios/Podfile` L46 | `PERMISSION_SPEECH_RECOGNIZER=1`（permission_handler のマクロ） | **Step 2** |
| `lib/.../widgets_intro_setting_layout_section.dart` L47 | レイアウト widget の**サンプル文言**として `'Allow Speech Recognition'` を使用 | Step 2 で権限表示を整理する際に合わせて見直し（パッケージ依存ではないので Step 1 では放置可） |
| `pubspec.lock` / `ios/Podfile.lock` | `speech_to_text` のロック情報 | **手で編集しない**。§5 のコマンドで自動再生成される |

---

## 5. 撤去後の再生成・整合

- `pubspec.yaml` から依存を消したら `flutter pub get` を実行 → `pubspec.lock` から `speech_to_text` / `speech_to_text_platform_interface` / `speech_to_text_windows` が自動で消える。
- `ios/Podfile.lock` の `speech_to_text` エントリは、次回 iOS ビルド時の `pod install`（Flutter が自動実行）で更新される。Step 1 の段階で iOS ビルドを行わない場合は lock が古いままでも問題ないが、commit に含めるなら `pod install` を一度通しておくと差分が綺麗になる。

---

## 6. 完了の目安

- コード・設定から `speech_to_text` / `SpeechToText` / `android.speech.RecognitionService` への参照が消えている（grep で 0 件）。
  - ※ `Permission.speech` 系（権限）は Step 2 で扱うため、この時点では残っていてよい。
- `flutter analyze` が通り（未使用 import なし）、`flutter build` がビルドできる。
- dev catalog を開くと、`Packages` カテゴリ（または speech_to_text アイテム）が消えている。

---

## 7. 作業チェックリスト

- [ ] `pubspec.yaml` から `speech_to_text` 依存を削除
- [ ] `lib/pages/dev/catalog/sections/packages/packages_speech_to_text_section.dart` を削除
- [ ] `catalog_page.dart` の import（L12）を削除
- [ ] `catalog_page.dart` の `Packages` カテゴリ定義（L48-50）を削除（§2 補足の判断に従う）
- [ ] `android/app/src/main/AndroidManifest.xml` の `RecognitionService` intent（L45-48）を削除 ← **outline 未記載の追加項目**
- [ ] `flutter pub get` で `pubspec.lock` を再生成
- [ ] `flutter analyze` で未使用 import / 警告がないことを確認
- [ ] （iOS をビルドする場合）`pod install` 経由で `Podfile.lock` を更新
