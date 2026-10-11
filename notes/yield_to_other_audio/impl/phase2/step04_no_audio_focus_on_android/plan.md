# Step 4 Android で、録音がオーディオフォーカスを取らないようにする

## 目的

Android で、momeo の録音が他のアプリの再生を止めないようにする。

録音ライブラリ（record_android）は、中断を扱う設定（`pauseResume`）だと、録音を始めるときにオーディオフォーカス（音を鳴らす権利）を独占する（`AUDIOFOCUS_GAIN`）。そのため他のアプリの再生が止まり、逆に他のアプリに権利を奪われると録音が止まる。権利が完全に移ると戻ってこないので、録音は止まったままになる。


| 項目（Android） | 今 | この step の後 |
| --- | --- | --- |
| 他のアプリの再生中に momeo を開いた | 他のアプリの再生が止まる | 止まらない（音は step 3 で捨てる） |
| momeo の録音中に他のアプリが鳴り始めた | 録音が止まり、戻らないことがある | 録音は続け、鳴っている間は捨てる |
| iOS | — | 変わらない（着信などの中断を扱うため `pauseResume` のまま） |


## やること

- `RecordConfig` の `audioInterruption` を、iOS は `pauseResume`、Android は `none` にする
- なぜ Android だけ `none` にするのかを、設定の横に書いておく

通話中は Android がマイクを通話に回し、momeo には無音が届く。中断を扱わなくても、通話の音を書き留めることはない。

## 参照する `spike/yield-to-other-audio` のコード


| ファイル | 場所 |
| --- | --- |
| `lib/stt/stt_listening_pipeline.dart` | `audioInterruption`（72〜76行目） |


フォーカスを取る処理の中身は、record_android 1.5.2 の `AudioRecorder.kt`（`requestAudioFocus`、237行目〜）にある。
