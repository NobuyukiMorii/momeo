# Step 10 仕様書を直す

## 目的

step 1〜9 の結果を、仕様書に反映する。


| 仕様書 | 直すところ |
| --- | --- |
| `notes/specs/listening_flow.md` | 認識パイプラインの図（iOS は 48kHz で録り、16kHz に落とす）と、その理由 |
| `notes/specs/listening_flow.md` | 新しい節「他のアプリの音との関係」 |
| `notes/specs/listening_recording_settings_panel.md` | 状態行の中断の表示 |


## やること

- 認識パイプラインの図を直し、iOS を 48kHz で録る理由（16kHz だと他のアプリの音までこもる）を書く
- 「他のアプリの音との関係」の節を足す
  - 目的2つ（他のアプリの声をメモにしない・他のアプリの音をこもらせない）
  - 録音が他のアプリの再生を止めないこと（iOS は `mixWithOthers`、Android はオーディオフォーカスを取らない）
  - 状況ごとの動きの表（鳴り始めた・鳴り止んだ・鳴っている中で開いた。Bluetooth のマイクか本体か、前面か背面か）
  - 状態行を中断の表示にすること、中断の終わりを待たずに再開すること、止めるときにセッションを手放すこと、Android の動き
- 録音設定パネルの状態行に、中断している間のドットと文言を書く

仕様書は無時制で書く（「新しく」「廃止」などは使わない）。

## 参照する `spike/yield-to-other-audio` のコード


| ファイル | 場所 |
| --- | --- |
| `notes/specs/listening_flow.md` | 認識パイプライン（112〜113・122行目）、「他のアプリの音との関係」（138〜161行目） |
| `notes/specs/listening_recording_settings_panel.md` | 状態行（21・25〜27行目） |

