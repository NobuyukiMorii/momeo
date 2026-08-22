# バックグラウンド録音 — スパイクで分かったこと

実装計画（`impl/outline.md`）の Step 1〜6 を `spike/background-recording` ブランチで一気に実装し、iOS はシミュレーター、Android はエミュレーターで動かした記録。計画に無かった発見を本実装へ引き継ぐための文書。実施: 2026-08-20〜21。

## ひとことで言うと

計画は成立する。両OSとも「OFF はバックグラウンドで止まり、ON はバックグラウンドでも録り続ける」ところまで動いた。
ただし**計画に無かった対応が4つ**必要だった（→「計画に無かった発見」）。本実装では最初から織り込める。

## 動作を確認できたこと

| 確認項目 | iOS（シミュレーター） | Android（エミュレーター） |
|---|---|---|
| OFF: バックグラウンドで停止 → フォアグラウンドで再開（Step 1） | ✅ 復帰後の発話も転写された | ✅ ログと appops で確認 |
| ON への切り替えの流れ（Step 3） | ✅ 開示 → OS 許可ダイアログ → 保存 | ✅（設定の直書きで代替） |
| ON: バックグラウンドでも録音が続く（Step 2・5） | ✅ バックグラウンド中の発話がメモに転写された | ✅ バックグラウンドでもマイク使用が継続 |
| microphone 型のサービス起動（Step 2） | — | ✅ `types=0x00000080` |
| 常駐通知が通常欄に出る（Step 4） | — | ✅ サイレント欄ではなく通常欄 |
| 通知の停止ボタン（Step 4） | — | ✅ 録音停止＋設定 OFF＋サービス停止 |
| バックグラウンド中の「録音中」ローカル通知（Step 6） | ✅ バックグラウンドで表示・フォアグラウンド復帰で消える | — |

iOS のバックグラウンド録音はデバッガ非接続のシミュレーターで動いた。強い材料だが、判定は release 実機で行う（→ `ios.md`）。

## 計画に無かった発見

### 1. iOS の通知許可は Podfile の1行が無いと黙って失敗する（Step 3・6）

- permission_handler は、Podfile のマクロで許可の種別ごとに機能を有効化する方式。`PERMISSION_NOTIFICATIONS=1` が無いと、`Permission.notification.request()` は**ダイアログを出さずに拒否を返す**
- 画面上は「有効にする」を押しても何も起きないように見え、原因に気づきにくい
- 対処: `ios/Podfile` の `GCC_PREPROCESSOR_DEFINITIONS` に追加（スパイクで追加済み）

### 2. 常駐通知の停止ボタンには TaskHandler が要る（Step 4）

- flutter_foreground_task は、通知ボタンの押下を **TaskHandler（別アイソレート）にしか届けない**。`android.md` の「TaskHandler は使わない」は録音については正しいが、停止ボタンを付けるなら転送役が要る
- 必要なのは三点セット。①押下をメインアイソレートへ転送するだけの最小 TaskHandler（`lib/stt/listening_foreground_service.dart`）、②`main()` での `FlutterForegroundTask.initCommunicationPort()`、③受け取り側の `addTaskDataCallback()`
- 録音・VAD・文字化は従来どおりメインアイソレートのまま。ハンドラーはイベント転送しかしない

### 3. iOS はバックグラウンド遷移の瞬間だとまだ「フォアグラウンド」扱いで、通知が表示されない（Step 6）

- paused を受けてすぐ出したローカル通知は、フォアグラウンドアプリ向けの表示判定（willPresent）に回されて**表示されずに終わる**。通知の登録自体は成功するため、エラーも出ない
- 対処: 1秒待ってから出す。待つ間にフォアグラウンドへ戻っていたら出さない（`lib/stt/listening_background_notice.dart`）

### 4. flutter_local_notifications は Android のビルド設定も変える（Step 6）

- iOS 専用の用途でも、Android 側に core library desugaring を要求し、有効にしないとビルドが落ちる
- 対処: `android/app/build.gradle.kts` に `isCoreLibraryDesugaringEnabled = true` と `desugar_jdk_libs` を追加（スパイクで追加済み）
- 22.x は API が名前付き引数に全面変更されている（`show(id:, title:, ...)` の形）

### 5. 細かい発見

- `flutter_foreground_task` は依存解決で 10.0.0 に決まる（11.0.1 は入らない）。実機検証と同じ版で好都合
- マージ後の AndroidManifest には、既存の Play Asset Delivery 由来で `dataSync` 型サービスと `FOREGROUND_SERVICE_DATA_SYNC` 権限も入っている。Play の FGS 申告（Step 8）は microphone だけで済まない可能性がある
- `flutter_foreground_task` は `RECEIVE_BOOT_COMPLETED` や再起動用レシーバーも持ち込む（momeo は使わない機能。審査で目を引くなら削る検討）

## 仮決めした点とその後の決定

| 論点 | 状態 |
|---|---|
| 停止ボタンの効き方 | **決定**。設定ごと OFF に切り替える（通知からの停止 = 同意の撤回。再開はアプリを開けばフォアグラウンド録音として自動で始まる）。文言はスパイクの「録音を停止」から「**バックグラウンド録音を停止**」に変える（何が止まるかを正確に言う） |
| フォアグラウンド表示中に停止ボタンを押されたとき | **本実装で直す**。スパイク実装はフォアグラウンドでも録音を止めてしまい、「このアプリを使っている時だけ録音」の表示と矛盾する。OFF に切り替えつつ録音は続ける形にする |
| 通知許可ゲートの適用範囲 | **決定**。ゲートは Android だけ（規約由来）。iOS は通知許可を ON の流れで求めるが、拒否されても ON にできるようにし、通知は出せる人にだけ出す。スパイク実装（両OSゲート）から iOS 側を変える。根拠: 通知拒否の経路を咎めた審査事例が見つからず、出回っている録音アプリにゲートする例も無い。Apple DTS もオレンジの点を録音中の表示と認めている（https://developer.apple.com/forums/thread/776949） |
| 許可を拒否されたときの表示 | 未設計。今は何も出ない。見せ方は Step 3 の着手時に詰める |

## 実機確認に残るもの

- iOS: release ビルド・実機でのバックグラウンド録音（ON と同じ重みで OFF 側も）
- Android: 停止 → 再開の後にマイクの音声が戻ることの、音声レベルでの確認（エミュレーターはホストマイクが不安定で確認しきれず。マイク使用の再開までは確認済み）
- `impl/outline.md` の「実機確認の宿題」（CallKit・長時間・スワイプ終了・OEM）はそのまま残る

## 環境メモ（エミュレーターで再現したいとき）

- Pixel 10 エミュレーターは Impeller だと文字が描画されない。`flutter run --no-enable-impeller` で回避する
- ホストマイクは `adb emu avd hostmicon` で有効になるが、不安定
- NeMo モデルの手置きは `scripts/place_android_device_models.sh`。ただし `flutter run` が再インストールでモデルを消すことがある

## スパイクのコード

`spike/background-recording` ブランチにある。`verified_implementation.md` の実装を、設定とライフサイクルへの結線込みで組み込み直した形になっており、本実装の出発点にできる。
