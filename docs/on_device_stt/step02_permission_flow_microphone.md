# Step 2: 権限フローをマイク中心に整理

## この文書について

- **位置づけ**: `outline.md` の「Step 2: 権限フローをマイク中心に整理」を、実コードを調査したうえで具体的な作業手順に落とし込んだもの。
- **対応コミット**: 1 step = 1 commit。本ステップは「speech_to_text 前提だった音声認識権限を外し、マイクのみのフローにする」ことだけを目的とする。
- **調査前提**: `outline.md` の記載を鵜呑みにせず、`speech` / `Permission.speech` / `SpeechRecognition` 系の参照をリポジトリ全体で grep し、実際の参照箇所と突き合わせた。その結果、**outline.md Step 2 に書かれていない撤去対象が2つ**見つかった（後述 §4）。
- **前提**: Step 1（speech_to_text パッケージ本体の撤去）は完了済み。Android マニフェストの `RecognitionService` intent も撤去済み。

---

## 1. このステップの境界

- 扱うのは **音声認識「権限」(B 系統)** のみ。パッケージ本体 (A 系統) は Step 1 で完了済み。
- **ドキュメントの扱い（決定）**: 音声認識「権限」に関する記述は、混乱を残さないよう **本ステップで整理する**（§3）。`outline.md` Step 12（仕様ドキュメントの改訂）は予定どおり残し、`listening_flow.md` / `overview.md` の改訂は Step 12 で行う。
- iOS のデプロイメントターゲット引き上げ（15.1）は **Step 3** の担当。本ステップでは触れない。

---

## 2. 撤去対象（コード・設定）

| # | 対象ファイル | 作業内容 | 現状の参照箇所 | outline 記載 |
|---|---|---|---|---|
| 1 | `lib/pages/permissions/permission_flow_page.dart` | `_permissionsByPlatform` の iOS リストから `Permission.speech` を**削除するだけ**（`[Permission.microphone]` にする）。マップ構造（ios/android の分岐）は将来のために残す | L31 | ○ |
| 2 | `lib/pages/permissions/permission_page.dart` | `_content` から `Permission.speech: {...}` エントリ（request/settings/unavailable）を削除 | L26-39 | ○ |
| 3 | `ios/Runner/Info.plist` | `NSSpeechRecognitionUsageDescription` のキーと文字列を削除 | L31-32 | ○ |
| 4 | `ios/Podfile` | `'PERMISSION_SPEECH_RECOGNIZER=1',` の1行を削除 | L46 | **✕（§4-A）** |
| 5 | `lib/pages/dev/catalog/sections/widgets/widgets_intro_setting_layout_section.dart` | 「Allow Speech Recognition」のサンプル要素を削除 | L44-49 | **✕（§4-B）** |

### 補足 2-1: フロー制御コードは変更不要（検証済み）

- 実アプリのステップ表示は `_stepLabel` が制御し、`_neededPermissions.length <= 1` のとき `null`（非表示）を返す。さらに `IntroSettingLayout` は `step == null` なら描画しない。
- したがって**マイクのみになれば「1/2」等のステップ表示は自動的に消える**。コード変更は不要。
- 複数権限制御（`_currentIndex` / `_advance` / `_neededPermissions`）は権限が1つでも正しく動くため、こちらも変更不要。

### 補足 2-2: dev catalog で消すのは「音声認識サンプル」だけ（検証済み）

- `widgets_intro_setting_layout_section.dart` は権限フローのロジックを通らず、`step: '1/2'` などの文字列を**手書きで直接** `IntroSettingLayout` に渡す「部品の見本帳」。
- よって実アプリの権限数とは無関係に、書いた文字列がそのまま表示される。
- 撤去対象は **「Allow Speech Recognition」の要素（L44-49）のみ**。残る「1/2」のマイク見本は「部品がステップ表記を描けること」の確認用なので**そのまま残してよい**（音声認識とは無関係）。

---

## 3. 撤去対象（ドキュメント）

> 音声認識「権限」に関する記述は本ステップで整理する（§1 の決定）。

### 3-A. 仕様: `docs/specs/permission_flow.md`

音声認識権限前提で全体が書かれているため、**マイクのみ前提**へ改訂する。

- L9 表: iOS の「マイク、音声認識」→「マイク」、表示画面も「マイク画面」のみに。
- L16: 権限の種類「microphone / speechRecognition」→「microphone」。
- L25-33 フロー図: iOS から「Speech Recognition permission if needed」の行を削除（iOS も Android と同じ「マイクのみ」になる）。
- L44-65 ステップ表示ルール／具体例: マイクのみになりステップが常に1つになるため、「1/2・2/2」前提の記述を簡素化し、**ステップ表示は常に非表示**である旨に整理。
- L67-74 参照デザインドキュメント: `PermissionSpeechRecognition*` への参照行を削除。
- L87 参考リンク: Apple の音声認識権限リンクは、マイクのみになるため必要に応じて整理。

### 3-B. デザイン資料（Figma エクスポート記録）→ 本ステップでは触らない（決定）

- `docs/design/03_screen_states/details/PermissionSpeechRecognition*.md`（3ファイル）と `state_catalog.md` は **Figma からのエクスポート記録**であり、Figma 本体には今も「Setting Recognition」画面（`CLAUDE.md`: `849:151` / `849:164` / `850:219`）が存在する。
- ドキュメントとデザインの整合はデザイン側の作業範囲のため、**本ステップでは変更しない**（そのまま残す）。

---

## 4. outline.md Step 2 に記載がなかった撤去対象（重要 / 抜け漏れ）

### 4-A. iOS Podfile の permission_handler マクロ

`ios/Podfile` L46 の `'PERMISSION_SPEECH_RECOGNIZER=1',`。

- permission_handler は `GCC_PREPROCESSOR_DEFINITIONS` のマクロで権限ごとのネイティブコードを有効化する仕組み。これを残すと `Permission.speech` 用のコードがビルドに含まれ続ける。
- マイク中心に整理する以上、**この1行を削除する**。直上の `'PERMISSION_MICROPHONE=1',`（L45）は**残す**。
- step01 のドキュメント §4 でも「Step 2」と予告済み。**outline Step 2 本文の抜け漏れ**。

### 4-B. dev catalog のレイアウトサンプル文言

`widgets_intro_setting_layout_section.dart` L44-49 の「Allow Speech Recognition」サンプル。

- 実アプリに存在しなくなる「音声認識画面」のサンプルがカタログに残るため削除する（詳細は §2 補足 2-2）。
- step01 のドキュメント §4 で「Step 2 で権限表示を整理する際に合わせて見直し」と予告済み。**outline Step 2 本文の抜け漏れ**。

---

## 5. 本ステップでは触れない（誤って巻き込まない）

| 対象 | 内容 | 扱い |
|---|---|---|
| `android/app/src/main/AndroidManifest.xml` | Android は元々 `[Permission.microphone]` のみ・`RECORD_AUDIO` のみ。Step 1 で `RecognitionService` intent 撤去済み | **変更不要** |
| `ios/Runner/Info.plist` の `NSMicrophoneUsageDescription`（L29-30） | マイク利用目的 | **残す** |
| `ios/Podfile` の `PERMISSION_MICROPHONE=1`（L45） | マイクのマクロ | **残す** |
| `permission_handler` 依存 | マイク権限で引き続き使用 | **削除しない** |
| `docs/specs/listening_flow.md` / `docs/specs/overview.md` | 確定トリガー・全体フローの記述 | **Step 12** で改訂 |
| `pubspec.lock` / `ios/Podfile.lock` | ロック情報 | **手で編集しない**。§6 で自動再生成 |

---

## 6. 撤去後の再生成・整合

- iOS の変更（Info.plist / Podfile）を反映するため、次回 iOS ビルド時の `pod install`（Flutter が自動実行）で `ios/Podfile.lock` が更新される。commit に含めるなら `pod install` を一度通して差分を綺麗にする。

---

## 7. 完了の目安

- コードから `Permission.speech` への参照が消えている（grep で 0 件 ※ docs を除く）。
- `ios/Runner/Info.plist` に `NSSpeechRecognitionUsageDescription` がない。
- `ios/Podfile` に `PERMISSION_SPEECH_RECOGNIZER=1` がない。
- iOS・Android とも**マイク権限のみ**を要求し、許可後にリスニングへ進む（マイクのみのためステップ表示は非表示）。
- `flutter analyze` が通り、`flutter build` がビルドできる。
- dev catalog のレイアウトサンプルに「Allow Speech Recognition」が残っていない。
- `docs/specs/permission_flow.md` から音声認識権限の記述が消え、マイクのみ前提に整合している（デザイン資料は対象外）。

---

## 8. 作業チェックリスト

### コード・設定
- [ ] `permission_flow_page.dart` L31 から `Permission.speech` を削除（iOS を `[Permission.microphone]` に。マップ構造は残す）
- [ ] `permission_page.dart` L26-39 の `Permission.speech` 表示定義を削除
- [ ] `ios/Runner/Info.plist` の `NSSpeechRecognitionUsageDescription`（L31-32）を削除
- [ ] `ios/Podfile` の `PERMISSION_SPEECH_RECOGNIZER=1`（L46）を削除 ← **outline 未記載の追加項目**
- [ ] dev catalog `widgets_intro_setting_layout_section.dart` の音声認識サンプル（L44-49）を削除 ← **outline 未記載の追加項目**

### ドキュメント
- [ ] `docs/specs/permission_flow.md` をマイクのみ前提に改訂（§3-A）
- [ ] デザイン資料（`PermissionSpeechRecognition*.md` / `state_catalog.md`）は触らない（§3-B 決定）

### 確認
- [ ] （iOS をビルドする場合）`pod install` 経由で `Podfile.lock` を更新
- [ ] `flutter analyze` で未使用 import / 警告がないことを確認
