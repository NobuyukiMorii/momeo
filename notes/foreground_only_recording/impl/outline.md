# 開いている間だけの録音への切り替え 実装計画

録音を「momeo を開いている間だけ」に絞り、背面録音（ほかのアプリを使っている間や、画面を消している間も録音を続けること）を iOS・Android の両方から外す。

背面録音は、iOS では何度直しても止まる場面が残った（Bluetooth イヤホンで何かを聞き始めたとき、中断の終わりの知らせが来ないときなど）。原因はどれも「背面では iOS が設定の切り替えや録音の始め直しを許さない」ことで、アプリ側では避けきれない。たまに止まる録音より、制約はあっても確実に録れる録音を選ぶ。

今と変わること:

- 今は、録音設定パネル（画面の上端から下りてくる面）で「このアプリを使ってる時だけ録音」と「ほかのアプリを使っていても録音」を選べる
- 切り替えたあとは、選択肢がなくなり、いつも「開いている間だけ」録音する。録音設定パネルはなくなる
- 録音している間は、画面を自動で消さない（iPhone・Android の自動ロックで録音が止まらないようにする）
- ロック画面の「録音中」の表示（Live Activity）、「録音が止まりました」の通知、Android の常駐通知はなくなる
- 「録音が一時的に中断されています」の表示もなくなる（録音設定パネルの状態行が担っていたもの。どこにも移さない）

変わらないこと:

- 他のアプリが鳴っている間は音を捨てる。Bluetooth のマイクの切り替え、機器の抜き差しや中断からの立て直しも残る（前面なら iOS に拒まれないので、むしろ確実に動く）
- 背面に回ったら録音を止め、前面に戻ったら新しいブロックで録音を始める（今の「このアプリを使ってる時だけ録音」と同じ）
- ログ（`DeviceLog` と開発用コンソール）

進め方:

- 1 step = 1 commit = 1つの目的
- 外す前の状態に、タグかブランチを付けておく（いつでも取り出せるように。付けるのは自分で行う）
- 見出しに【iOS】【Android】【共通】を付ける
- どの step の後でもビルドが通り、録音できる状態を保つ。動きを先に変え（Phase 1）、使われなくなったものを後で消す（Phase 2）
- 各 step は `phaseN/stepNN_名前/` に置く（計画は `plan.md`。説明資料の HTML は、頼んだときだけ作る）
- Swift・Kotlin・Info.plist・AndroidManifest を変えた step は、`make run` し直して確かめる

---

## 全体の流れ

```text
Phase 1  動きを変える（画面を消さない・いつも開いている間だけ）   ← 使い心地が変わるのはここだけ
  ↓ しばらく使って確かめる
Phase 2  背面録音のための仕組みを消す                            ← 量は多いが、ほぼ削除
Phase 3  仕様書とストアの資料
```

---

## Phase 1 動きを変える

| step | やること |
| ---- | ------------------------------------------------------------ |
| 1    | 【共通】録音している間は、画面を自動で消さない |
| 2    | 【共通】背面録音の選択肢と録音設定パネルを外し、いつも開いている間だけ録音する |

※ step 1 は `wakelock_plus` で、リスニングを始めたら画面を消さないようにし、止めたら元に戻す。電源ボタンで消したときは、今と同じく背面に回った扱いで録音が止まる。

※ step 2 で消すのは、`listening_recording_settings_panel.dart`・`recording_option_cards.dart`・`background_recording_disclosure_dialog.dart`・`recording_scope.dart`、`backgroundRecordingProvider` と設定の保存（`app_settings_repository.dart` の該当部分・`PreferencesKeys` の2つのキー）。`listening_providers.dart` では、背面で続けるかの分かれ道（`_keepsRecordingInBackground`）を「いつも止める」に固定し、設定の切り替えへの反応を消す。この時点で Live Activity・止まった知らせ・常駐通知は呼ばれなくなる（コードは残っている。消すのは Phase 2）。パネルに触れたら本文の文字選択を外す仕組み（`NativeMemoListController` と、ネイティブ側の `clearSelection`）も、使う側がなくなるので消す。中断中かどうかの状態（`recordingPaused`・`onPausedChanged`）も、表示する場所がなくなるので消す。

※ 端末に残っている設定値（`background_recording_enabled` など）は読まなくなるだけで、害はない。

### Phase 2 に進む前に確かめること

| 確かめること | iOS | Android |
| --- | --- | --- |
| 録音中に放っておいても画面が消えず、録音が続くか | 未確認 | 未確認 |
| 電源ボタンで消す・ホームに戻ると録音が止まり、戻ると新しいブロックで始まるか | 未確認 | 未確認 |
| Bluetooth イヤホンで他のアプリが鳴ったとき、前面なら録音が止まらず、音もこもらないか | 未確認 | ― |
| 画面を点けっぱなしにしたときの電池の減り・発熱が、困る程度でないか | 未確認 | 未確認 |

## Phase 2 背面録音のための仕組みを消す

使われなくなったものを消す。どの step の後でもビルドが通るよう、使う側（Dart）とネイティブを OS ごとにまとめて消す。

| step | やること |
| ---- | ------------------------------------------------------------ |
| 3    | 【iOS】Live Activity と「録音が止まりました」の通知を消す |
| 4    | 【iOS】背面で音を扱う宣言を外し、マイクの説明文を直す |
| 5    | 【Android】フォアグラウンドサービスと常駐通知を消す |
| 6    | 【共通】録音の流れから、背面のためだけの工夫を外す |

※ step 3 で消すのは、`listening_live_activity.dart`・`listening_stop_alert.dart`・`ListeningStopAlertChannel.swift` と `AppDelegate.swift` での登録、`main.dart` の後片付けの呼び出し、`ios/MomeoWidgets/`（ウィジェットのターゲットごと）、App Group（`group.jp.momeo`）、`Info.plist` の `NSSupportsLiveActivities`、`live_activities`。ウィジェットのターゲットは `project.pbxproj` に深く入り込んでいるので、Xcode で外す。

※ step 4 で外すのは、`Info.plist` の `UIBackgroundModes`（audio）。`NSMicrophoneUsageDescription` から「ほかのアプリを使っていても録音」のくだりを消す。

※ step 5 で消すのは、`listening_foreground_service.dart`、`main.dart` の `FlutterForegroundTask.initCommunicationPort()`、`listening_providers.dart` の常駐通知の停止ボタンの受け取り、`AndroidManifest.xml` の `FOREGROUND_SERVICE`・`FOREGROUND_SERVICE_MICROPHONE` とサービス本体、`flutter_foreground_task`。通知の許可を尋ねている箇所が残っていれば、それも消す。

※ step 6 で外すのは、`stt_listening_pipeline.dart` の背面専用の分かれ道。オーディオの設定をし直さない再開（`keepsAudioSession`・`manageAudioSession`・`_isInBackground`）、Bluetooth のマイクの戻しを後回しにする処理、Bluetooth のマイクを手放せないときに録音ごと止める処理（`_releaseRecordingForOtherAudio`・`_releasedForOtherAudio`）。前面に戻ったときの立て直し（`ensureRunning`）は、背面では必ず止まっているので「始め直す」だけになる。状態の印の表もあわせて直す。

※ 残すもの: `AudioSessionChannel`（iOS・Android）、他のアプリの音の見張り、録音の見張り（`_watchdog`）、機器の切り替え直後の中断の見張り、`DeviceLog`。

## Phase 3 仕様書とストアの資料

| step | やること |
| ---- | ------------------------------------------------------------ |
| 7    | 【共通】仕様書を直す |
| 8    | 【共通】ストア提出の資料とスクリーンショットを見直す |

※ step 7 の対象は `notes/specs/` の `listening_flow.md`（背面録音・止まったときの知らせの節）・`overview.md`。`listening_recording_settings_panel.md` は消す。仕様書は無時制で書く。

※ step 8 では、`notes/release/store_submission/background_recording_submission.md`（背面録音の審査向けの説明）を `submission_notes.md` に置き換え、プライバシーポリシー（`docs/privacy.html`）の背面録音の段落を直す。ストアのスクリーンショットは、録音設定パネルが写っているので撮り直す（撮影は手元で行う）。

※ `notes/background_recording/`・`notes/background_stop_recovery/`・`notes/yield_to_other_audio/` は、経緯の資料として残す。
