# Step 1 2つの spike のコミットを main に取り込む

## 目的

`spike/ios-speech-transcriber` と `spike/android-speech-recognizer` で作った OS の文字起こしを、そのまま main に入れる。

コードは書かない。

git の操作だけで終わる step。


| 項目 | 今 | この step の後 |
| --- | --- | --- |
| iOS 26 以上の端末 | SenseVoice で文字にする | SpeechTranscriber で文字にする |
| Android 13 以上で、言語のモデルが入っている端末 | SenseVoice で文字にする | SpeechRecognizer で文字にする |
| それ以外の端末 | SenseVoice で文字にする | SenseVoice で文字にする（今のまま） |
| 文字にする言語 | 自動で判定する | OS の文字起こしでは、端末の「優先する言語」のうち使える最初のものに決まる |


OS の文字起こしを使う端末では、SenseVoice を読み込まない。

## やること

- 取り込む前に、main に `notes/os_transcription/` 以外の変更が無いことを確かめる
- `spike/android-speech-recognizer` を main に fast-forward（コミットをそのまま足すだけの取り込み）で取り込む

```bash
git merge --ff-only spike/android-speech-recognizer
```

`spike/android-speech-recognizer` は `spike/ios-speech-transcriber` の続きなので、これ1回で2つのコミットが入る。


| コミット | 中身 |
| --- | --- |
| `34e08c8` | iOS の SpeechTranscriber |
| `fd493bd` | Android の SpeechRecognizer |


main の先頭（`bc7dac0`）から枝分かれしていないので、ぶつかる箇所は無い。

※ git の操作はユーザーが行う。

※ この step では新しいコミットを作らない（取り込んだ2つのコミットが、この step のコミットにあたる）。

## 確かめること

- iOS と Android の両方で `make run` し直し、起動時のログに `[sttEngine] OS の文字起こしを使います` が出ること
- 話した内容が、メモとして一覧に出ること

## この step では見ない部分

spike には、調べるために入れたログが残っている。片付けるのは step 2。
