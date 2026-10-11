# Step 5 Bluetooth のマイクを手放し、イヤホンを音楽用に戻す（iOS）

## 目的

Bluetooth イヤホンのマイクで録っているときも、他のアプリが鳴っている間は、イヤホンを音楽用の方式（A2DP）に戻して、他のアプリの音をこもらせない。

マイクだけ本体に指名しても、録音の設定に「Bluetooth のマイクを使ってよい（`allowBluetooth`）」が入っている限り、イヤホンは通話用の方式（HFP）のまま。設定からこの項目を外す必要がある。ただし iOS は、背面での設定の差し替えも録音の開き直しも拒否する（spike の実機ログで確認）。


| 状況（Bluetooth のマイクで録っている） | 今 | この step の後 |
| --- | --- | --- |
| 前面で他のアプリが鳴り始めた | イヤホンは通話用のまま（こもる） | 録音を止めずに Bluetooth のマイクを手放す。イヤホンは音楽用、マイクは本体になる |
| 背面で他のアプリが鳴り始めた | イヤホンは通話用のまま（こもる） | 録音を止めてイヤホンごと手放す |
| 他のアプリが鳴っている中で録音を始めた | 通話用で開く（こもる） | Bluetooth のマイクを使わない設定で開く |
| 鳴り止んだ | — | 録音を開き直して、Bluetooth のマイクに戻す。背面では開き直せないので、前面に戻ったときに再開する |


本体のマイクで録っているときは設定を替えない（捨てるだけ）。設定を替えなければ、背面でも鳴り止めばそのまま再開できる。

## やること

- 窓口に `isBluetoothMicInUse`（今の入力が HFP か）と `releaseBluetoothMic`（`allowBluetooth` を外したカテゴリに差し替える）を足す
- 録音の設定を `_buildRecordConfig` で2通り作る（Bluetooth のマイクを使う・使わない）。他のアプリが鳴っている間は使わない設定で開く
- 録音を開く処理を `_openRecordingStream` の1か所にまとめ、「今の録音が Bluetooth のマイクを手放している」印 `_bluetoothMicReleased` を、開いた設定から決める
- 鳴り始めて Bluetooth のマイクで録っていれば、`releaseBluetoothMic` で手放す。背面で拒否されたら、録音を止めてセッションごと手放す（`_releasedForOtherAudio`。この間は見張りに作り直しをさせない）
- 鳴り止んだとき、`_bluetoothMicReleased` が立っていれば、その場で録音を開き直す（設定の差し替えだけだと録音エンジンが黙って止まるため）。`_restartRecording` に作り直すきっかけ（`reason`）を渡し、ログを出し分ける
- 録音を開いた直後と Bluetooth のマイクを手放した直後の3秒は、鳴っていない判定を数えない（自分で起こした経路の組み直しで他のアプリの再生が一瞬途切れ、鳴り止んだと取り違えて開き直すと、相手の再生を止めてしまうため）
- 印の一覧に `_bluetoothMicReleased`・`_releasedForOtherAudio`・`_otherAudioSettlesAt` を書き足す

## 参照する `spike/yield-to-other-audio` のコード


| ファイル | 場所 |
| --- | --- |
| `ios/Runner/AudioSessionChannel.swift` | メソッド名（11〜12行目）、受け取り（26〜29行目）、`handleIsBluetoothMicInUse`（42行目〜）、`handleReleaseBluetoothMic`（48行目〜） |
| `lib/platform/audio_session_channel.dart` | `isBluetoothMicInUse`（26行目〜）、`releaseBluetoothMic`（32行目〜） |
| `lib/stt/stt_listening_pipeline.dart` | 3秒の待ち（53〜55行目）、2通りの設定（57〜87行目）、印の一覧（142〜149行目）、状態（165〜168行目）、`_openRecordingStream`（283〜293行目）、`_reopenRecordingStream`（298行目〜）、見張りの `_releasedForOtherAudio`（385〜386行目）、`_restartRecording` の `reason`（443行目〜）、`_currentRecordConfig`（514〜516行目）、`_isOtherAudioSettling`・`_waitForOtherAudioToSettle`（547〜555行目）、`_checkOtherAudio` の待ち（577〜581行目）、`_yieldToOtherAudio` の Bluetooth の部分（606〜619行目）、`_takeBackFromOtherAudio` の開き直し（626〜639行目）、`_releaseRecordingForOtherAudio`（642行目〜） |


spike の `_takeBackFromOtherAudio` の開き直しは、`_interrupted` も見ている（step 6）。この step では `_bluetoothMicReleased` だけを見る。

`releaseBluetoothMic` のカテゴリのオプションは、Dart 側の `_buildRecordConfig(allowsBluetoothMic: false)` と揃える（Swift 側にそう書いておく）。

この step は大きいので、実装中に「前面で手放す」と「背面で録音ごと手放す」の2つに分けてもよい。
