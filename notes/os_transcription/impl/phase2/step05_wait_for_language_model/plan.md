# Step 5 言語のモデルのダウンロード中は、準備ゲート画面にそう出して待つ

## 目的

OS の文字起こしは、言語ごとのモデルを OS が端末にダウンロードして使う。

そのモデルがまだ端末に無いとき、ダウンロードが終わるまで準備ゲート画面で待ち、その間は「言語のモデルをダウンロードしています」と出す。

終われば、アプリを開き直さなくても、そのままリスニングを始められる。


| 項目 | 今 | この step の後 |
| --- | --- | --- |
| iOS でモデルが無いとき | prepare の中でダウンロードが終わるまで黙って待つ（画面はアプリ名のまま） | すぐに「ダウンロード中」と返し、画面にそう出す。終わったら先へ進む |
| Android でモデルが無いとき | ダウンロードを頼み、「使えない」と返す（step 4 の後は「この端末では使えません」になってしまう） | ダウンロードを頼み、「ダウンロード中」と返す。終わったら先へ進む |
| Android でダウンロードが進行中のとき | 頼み直す | 頼み直さず、「ダウンロード中」と返す |
| 待ち方 | — | エンジンの準備が5秒おきに prepare を呼び直し、入ったかを確かめる。失敗の回数には数えない |


「この端末では使えません」は、端末も言語も対応していないときだけに出る。

## やること

### prepare の返事を3つにする

今の返事は `available`（使えるか）と `detail`（理由）の2つ。

これを `state`（`ready`・`downloading`・`unsupported` のどれか）と `detail` にする。

| state | 意味 |
| --- | --- |
| `ready` | 言語のモデルが入っていて、すぐ使える |
| `downloading` | 対応している言語だが、モデルのダウンロードが終わっていない |
| `unsupported` | 端末か言語が対応していない |


### iOS（`SpeechTranscriberChannel.swift`）

- 言語を決めたあと、その言語のモデルが入っているかを `SpeechTranscriber.installedLocales` で確かめる
- 入っていなければ、ダウンロード（`AssetInventory` の `downloadAndInstall`）を待たずに始めて、`downloading` を返す
- ダウンロードの途中で prepare がまた呼ばれたら、始め直さずに `downloading` を返す（進行中のダウンロードを1つだけ覚えておく）
- ダウンロードが失敗していたら、次の prepare で始め直す

### Android（`SpeechRecognizerChannel.kt`）

- 優先する言語が `installedOnDeviceLanguages` にあれば `ready`
- `pendingOnDeviceLanguages`（ダウンロード待ち・進行中）にあれば、頼み直さずに `downloading`
- `supportedOnDeviceLanguages` にあれば、`triggerModelDownload` で頼んで `downloading`

### Dart

- `OsTranscriberStatus` を `state` で持つように変える
- `stt_providers.dart` で、`downloading` なら専用のエラー（例: `SttModelDownloadingError`）を投げる
  - このエラーのときは `_scheduleRetry` を使わず、5秒後に準備をやり直す（`_consecutiveFailures` を増やさないので、「アプリを再起動してください」にならない）
- `preparation_gate_page.dart` にフェーズ「言語のモデルをダウンロード中」を足し、`ActivityDotsText('言語のモデルをダウンロードしています')` を出す（進み具合の % は出さない。OS から取れない端末があるため）

## 確かめること

Swift と Kotlin を変えるので、iOS と Android の両方で `make run` し直す。

- iOS：設定（一般 → 言語と地域）で、まだ使ったことのない言語を優先する言語の1番目にして起動する。「言語のモデルをダウンロードしています」が出て、終わったらリスニングに進むこと
- Android：設定で言語のモデル（端末内の音声認識の言語）を1つ削除してから、その言語を優先する言語の1番目にして起動する。同じく、ダウンロードの表示のあとにリスニングに進むこと
- Android で `triggerModelDownload` を呼んだとき、OS が確認の画面や通知を出すかを見る（出る場合は、準備ゲート画面の文言を合わせる）
- 確かめたら、言語の設定を元に戻す
