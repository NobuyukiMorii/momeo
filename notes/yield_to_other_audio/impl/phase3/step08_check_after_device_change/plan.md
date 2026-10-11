# Step 8 機器の抜き差しのあと、すぐ録音の生死を確かめる（iOS）

## 目的

録音中に Bluetooth イヤホンをつないだ直後の、聞き取りの抜けを縮める。

イヤホンがつながると、録音エンジンが黙って止まることがある。今は見張りが5秒待ってから作り直すので、その間に話した内容が抜ける。


| 項目（iOS） | 今 | この step の後 |
| --- | --- | --- |
| 録音中（前面）に Bluetooth イヤホンをつないだ | 約6秒、聞き取りが抜ける | 約1〜1.5秒で作り直す |
| 録音中に外した | 録音は続く | 変わらない（止まっていなければ何もしない） |
| 背面でつないだ | 前面に戻るまで再開しない | 変わらない（背面では開き直せない） |


## やること

- iOS 側の窓口に、機器がつながった・外れたことを流す線（EventChannel）を足す。momeo 自身の設定変更による経路の組み直しは流さず、機器の抜き差し（`newDeviceAvailable`・`oldDeviceUnavailable`）だけを流す
- Dart 側の窓口に `deviceChanges` を足す
- パイプラインで知らせを受けたら、1秒待ってから、0.5秒以上音が届いていなければ作り直す（知らせが続けて届いたときは、最後の1回から数える。中断中・譲るために手放している間は確かめない）
- 録音を始めたら購読し、止めたら購読をやめる

## 参照する `spike/yield-to-other-audio` のコード


| ファイル | 場所 |
| --- | --- |
| `ios/Runner/AudioSessionChannel.swift` | 冒頭のコメント（4〜6行目）、`deviceChangesChannelName`・流す係（14〜17行目）、線を立てる（37〜39行目）、`AudioDeviceChangeStreamHandler`（74行目〜） |
| `lib/platform/audio_session_channel.dart` | `_deviceChanges`・`deviceChanges`（13〜18行目） |
| `lib/stt/stt_listening_pipeline.dart` | 待ち時間（43〜44行目）、購読（127行目）、予約（159行目）、`start()`（211行目）、`stop()`（221〜222行目）、抜き差しの見張り（395〜430行目） |

