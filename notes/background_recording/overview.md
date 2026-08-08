# バックグラウンド録音 — 概要

アプリが背面にいる間も録音を継続できるのか、**技術的な可否**と**ストア規約上の可否**を整理した文書群の入り口。

| 文書 | 内容 |
|---|---|
| `overview.md`（この文書） | 結論、現状、両OS共通の制約、実務リスク |
| `ios.md` | iOS の必要な設定と実機検証の結果 |
| `android.md` | Android の必要な設定と実機検証の結果 |
| `store_policy.md` | Apple / Google Play の規約、提出物、実装要件 |
| `verified_implementation.md` | 検証に使った実装の全文（破棄済み。着手時の出発点） |

- **調査日**: 2026-07-27（規約・技術調査）、2026-08-01（実機検証）
- **対象**: `record` 6.2.1（`pubspec.yaml` の指定は `^6.1.2`）、`flutter_foreground_task` 10.0.0
- **きっかけ**: 現状 momeo は背面に入ると録音が止まる。継続できるようにしたいが、OS とストアが許すのかを先に確認したい

---

## 結論

**技術的にも規約的にも可能。両OSとも実機で動作を確認済み。**

- 背面で止まるのは仕様ではなく、**単に設定を入れていないから**
- **iOS** は**動かすだけ**なら `Info.plist` の4行と `RecordConfig` の3設定で済む。ただし**ストアに出すには、背面での「録音中」表示の実装が別に要る**（Android は常駐通知が OS 側で強制されるが、iOS には相当する仕組みがない）（→ `ios.md`）
- **Android** は `microphone` タイプのフォアグラウンドサービスが必須。`record` 単体では不可で `flutter_foreground_task` が要る（→ `android.md`）
- **録音・VAD・文字化のパイプラインを別アイソレートへ引っ越す必要はない**。両OSとも現行の `SttListeningPipeline` の構造のまま背面で動いた
- 規約上は「録音アプリの正当な用途」として認められるが、**録音していること自体を明示する義務は、外部送信の有無に関係なく消えない**（→ `store_policy.md`）
- momeo は**オンデバイス完結・外部送信なし**なので、第三者提供まわりの条項は素直にクリアできる

残る最大のリスクは実装ではなく **iOS の審査**（→ `store_policy.md`）。

---

## 調査時点の実装

背面で録音が止まる原因は、OS の制限を解除する設定を一切入れていないことにある。

| ファイル | 状態 |
|---|---|
| `ios/Runner/Info.plist` | `NSMicrophoneUsageDescription` のみ。`UIBackgroundModes` の宣言なし |
| `android/app/src/main/AndroidManifest.xml` | `RECORD_AUDIO` のみ。フォアグラウンドサービス関連の宣言なし |

つまり、OS が背面遷移の時点でマイクを切っている状態である。

---

## 両OS共通の制約

**「フォアグラウンドで開始 → 背面に回っても継続」は可能だが、「バックグラウンドから新規に開始」はできない。**

Android 公式ドキュメントの記述が明確である。制限は1つではなく、バージョンごとに積み上がっている。

- アプリがフォアグラウンドにある状態でマイクサービスを開始した場合、背面に移動した後も音声キャプチャを継続できる
- Android 11 以降、バックグラウンドから起動したフォアグラウンドサービスは、起動自体はできてもマイク・カメラ・位置情報にアクセスできない
- Android 12 以降、そもそもバックグラウンドからのフォアグラウンドサービス起動が原則禁止（一部の免除あり）
- Android 14 以降、`microphone` など while-in-use 権限を要する型は起動時に権限チェックが入り、バックグラウンドからの開始は `SecurityException` になる
- Android 14 以降、`BOOT_COMPLETED`（端末再起動）からの `microphone` サービス起動も禁止

この制約から、**「端末を再起動したら勝手に聞き始める」「アプリを一度も開かずに録り始める」は実装不可能**であり、ユーザーが必ず一度アプリを開いて開始する形になる。iOS も、ユーザーがアプリスワイプで強制終了した場合は自力で復帰できない点は同じ。

なお Android 15 で追加された「6時間で強制終了」のフォアグラウンドサービス タイムアウトは `dataSync` と `mediaProcessing` が対象で、**`microphone` は対象外**（調査時点の公式ドキュメントでも対象は2種類のまま）。長時間の常時リスニング自体は制度上は止められない。

---

## 設定の ON / OFF が効くタイミング

`store_policy.md` の要件から、バックグラウンド録音には設定での ON / OFF が要る。**どちらの OS もアプリの再起動は不要**だが、何をもって「効く」のかが OS で違う。

| | ON にした瞬間 | OFF にした瞬間 |
|---|---|---|
| Android | 常駐サービスを起動する。**その場で効く** | 常駐サービスを停止する。**その場で効く** |
| iOS | 何も起きない。**次に背面へ回ったときに効く** | 何も起きない。**次に背面へ回ったときに効く** |

Android の `startService()` / `stopService()` は実行時の操作なので、設定と挙動が同じタイミングで動く。マニフェストの宣言は静的だが、それは「サービスを立てられる状態」を作るだけで、立てるかどうかは実行時の判断になる。

iOS の `UIBackgroundModes` はアプリバイナリの性質で、**実行時に切り替えられない**。一度入れたら常に宣言された状態になる。挙動を分けるのは、背面へ回ったときにアプリ自身が録音を止めるかどうかであり、設定を切り替えた瞬間には何も起きない（→ `ios.md`）。

いずれにせよ設定と挙動の間に時間差があるため、UI 側の文言は現在の状態の報告ではなく、これから背面に回ったときにどうなるかの予告として読まれる。

---

## 規約以外の実務リスク

- **バッテリー消費**: 常時録音に加えて sherpa-onnx / NeMo の推論を回し続けるため消費が大きい。低評価の主因になりやすい
- **Android OEM のプロセスキル**: Xiaomi や OPPO などは Google の規定と無関係にフォアグラウンドサービスを停止させる。「録れていなかった」という不具合報告につながる
- **マイクの奪い合い**: 通話・音声アシスタント・他の録音アプリがマイクを取ると録音が止まる。両OSとも起こりうるため、止まったことをユーザーに伝える経路が要る
- **iOS の強制終了**: ユーザーがアプリスワイプで終了すると再開できず、自動復帰の手段もない
- **ストレージ**: 長時間の連続録音はファイルサイズが膨らむ。分割保存と古いデータの扱いを決めておく
- **審査の心証**: 「常時聞いている」機能はレビュワーの目が厳しくなる領域。オンデバイス完結であることを審査メモに明記した方がよい

---

## 参考リンク

### Apple
- [UIBackgroundModes（現行のキーリファレンス）](https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [About the orange and green indicators in your iPhone status bar](https://support.apple.com/en-us/108331)
- [Audio Guidelines By App Type](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/AudioGuidelinesByAppType/AudioGuidelinesByAppType.html) — アーカイブ済み（2017年更新）
- [App Review - Background Audio capabilities not accepted](https://developer.apple.com/forums/thread/91872) — `audio` モードのリジェクト事例
- [AVAudioSessionErrorCodeCannotStartRecording when recording in the background](https://developer.apple.com/forums/thread/120038) — 中断復帰の失敗報告
- [Getting 561015905 while trying to initiate recording when the app is in background](https://developer.apple.com/forums/thread/751866)

### Android
- [Foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types)
- [Restrictions on starting foreground services from the background](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)
- [Foreground service timeouts](https://developer.android.com/develop/background-work/services/fgs/timeout)
- [Behavior changes: Android 15](https://developer.android.com/about/versions/15/behavior-changes-15)
- [Behavior changes: all apps（Android 9）](https://developer.android.com/about/versions/pie/android-9.0-changes-all)
- [Privacy indicators（Android 12+）](https://developer.android.com/training/permissions/explaining-access)

### パッケージ
- [record — バックグラウンド録音ドキュメント](https://github.com/llfbandit/record/blob/main/doc/bg_recording.md)
- [flutter_foreground_task](https://pub.dev/packages/flutter_foreground_task)

---

## 関連ドキュメント

- `notes/research/on_device_stt/continuous_listening_limitation.md` — 常時リスニングの限界（フォアグラウンド前提の調査）
- `notes/research/microphone_permission_revocation.md` — マイク権限の取り消し
- `notes/specs/listening_flow.md` — リスニングフローの仕様
- `notes/specs/permission_flow.md` — マイク許可フローの仕様
