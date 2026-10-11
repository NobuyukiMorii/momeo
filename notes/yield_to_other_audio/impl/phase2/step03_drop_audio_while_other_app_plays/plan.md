# Step 3 他のアプリが鳴っている間は、聞いた音を捨てる

## 目的

他のアプリ（YouTube・語学教材など）が鳴っている間は、マイクで拾った音を書き留めない。スピーカーから出た他人の声がメモになるのを防ぐ。

他のアプリが鳴っているかは 0.5秒おきに確かめる（iOS は `isOtherAudioPlaying`、Android は音楽・動画などのメディア再生だけを見る `isMusicActive`。通知音や着信音は含まない）。


| 項目 | 今 | この step の後 |
| --- | --- | --- |
| スピーカーから出た他のアプリの声 | 文字化してメモになる | 捨てる |
| 話している途中で他のアプリが鳴り始めた | 他のアプリの音が混ざって文字化される | その発話は文字化せずに捨て、「.」を消す |
| 他のアプリが鳴っている中で録音を始めた | 文字化する | 最初から捨てる |
| 鳴り止んだあと | — | 鳴っていない状態が2秒続いたら、書き留めを再開する |


マイクは開いたまま、音を音声 isolate へ渡す前に捨てる。マイクを閉じると iOS が背面で momeo を眠らせ、鳴り止んでも再開できなくなるため。

## やること

- 窓口に `isOtherAudioPlaying` を足す
  - iOS：`AVAudioSession.isOtherAudioPlaying` を返す
  - Android：窓口 `AudioSessionChannel`（Kotlin）を新しく作り、`AudioManager.isMusicActive` を返す。`MainActivity` で保持する
- パイプラインで、他のアプリが鳴っているかを 0.5秒おきに確かめる（確かめている最中・作り直しの最中は重ねない。確かめられないときは鳴っていない扱い）
- 鳴っている間は、届いたチャンクを捨てる（見張りが見る「最後に音が届いた時刻」は更新する）
- 鳴り始めたら、VAD を空にして区切りの途中の発話を捨て、「発話を捨てた」専用の知らせ `onSpeechDiscarded` を出す。受け取る側は `withSpeechDiscarded` で発話中と結果待ちを解く
- 鳴っていない判定が4回（2秒）続いたら、書き留めを再開する
- 録音を始める前に鳴っているかを確かめ、鳴っていれば最初から捨てる
- パイプラインに「状態の印の一覧」コメントを作り、`_interrupted`・`_restarting`・`_otherAudioPlaying` を書く

※ この step の後も、iOS の Bluetooth のマイクを使っている間は、他のアプリの音はこもったまま。step 5 で解消する。

※ Android は step 4 まで、録音がオーディオフォーカスを取る（今と同じ）。momeo を開くと他のアプリの再生が止まり、他のアプリが鳴ると録音が止まったまま戻らないことがある。

## 参照する `spike/yield-to-other-audio` のコード

spike には step 5・6 の処理も入っているので、捨てる・再開するだけの部分を見る。`_checkOtherAudio` の「経路の組み直しの直後は数えない」（577〜581行目）と、`_yieldToOtherAudio` の Bluetooth の部分（606行目〜）は step 5 で足す。


| ファイル | 場所 |
| --- | --- |
| `android/app/src/main/kotlin/jp/momeo/AudioSessionChannel.kt` | ファイル全体（36行） |
| `android/app/src/main/kotlin/jp/momeo/MainActivity.kt` | 保持（13〜14行目）、作成（29〜32行目） |
| `ios/Runner/AudioSessionChannel.swift` | `isOtherAudioPlayingMethod`（10行目）、受け取り（24〜25行目） |
| `lib/platform/audio_session_channel.dart` | `isOtherAudioPlaying`（20行目〜） |
| `lib/stt/stt_listening_pipeline.dart` | 間隔と回数（50〜52行目）、`onSpeechDiscarded`（97・117〜119行目）、印の一覧（131〜150行目）、状態（161〜164・169行目）、`start()` の確かめ（188〜190行目）と見張りの開始（213行目）、`stop()` の見張りの停止（224行目）、`_onAudioChunk` の捨てる（326〜327行目）、`_isOtherAudioPlaying`（519行目〜）、`_startOtherAudioWatch`（537行目〜）、`_stopOtherAudioWatch`（557行目〜）、`_checkOtherAudio`（567行目〜）、`_yieldToOtherAudio`（598〜604行目）、`_takeBackFromOtherAudio`（625行目〜） |
| `lib/providers/listening_providers.dart` | `withSpeechDiscarded`（96行目〜）、渡す（294行目）、`_onSpeechDiscarded`（447行目〜） |


この step の `_takeBackFromOtherAudio` は、印を下ろして書き留めを再開するだけ（開き直しは step 5・6 で足す）。
