# Step 9 【iOS】同梱した認識モデルを消す

## 目的

iOS のアプリに同梱している SenseVoice（約239MB）と、その置き場所を Dart に返す窓口を消す。

アプリのサイズが、その分小さくなる。

動きは変えない（step 8 で、Dart から呼ばれなくなっている）。


| 項目 | 今 | この step の後 |
| --- | --- | --- |
| アプリに入っているもの | SenseVoice の本体（`model.int8.onnx`）と tokens（`tokens.txt`） | 入っていない |
| 窓口 `SttModelChannel` | 登録されている（呼ばれていない） | 無い |
| `make run`・`make build-ios` | ビルドの前に、モデルを `ios/Runner/Models/` へ置く | 置かない |


## やること

### 消すもの

| ファイル | 中身 |
| --- | --- |
| `ios/Runner/Models/`（フォルダごと） | SenseVoice の本体と tokens。実体は git では無視されていて、手元にだけある |
| `ios/Runner/SttModelChannel.swift` | モデルの置き場所を Dart に返す窓口 |
| `scripts/place_ios_models.sh` | モデルを `ios/Runner/Models/` へ置くスクリプト |
| `scripts/register_ios_files.rb` | モデルと `SttModelChannel.swift` を Xcode に登録するための、一度きりのスクリプト |


### 直すもの

- `ios/Runner.xcodeproj/project.pbxproj`
  - `Models` グループと、`model.int8.onnx`・`tokens.txt` の参照・Copy Bundle Resources の行を消す
  - `SttModelChannel.swift` の参照・Compile Sources の行を消す
- `ios/Runner/AppDelegate.swift`
  - `SttModelChannel` の登録を消す
- `scripts/run_on_device.sh`
  - `place_ios_models.sh` の呼び出し（と、そのコメント）を消す
- `Makefile`
  - `build-ios` の `place_ios_models.sh` を消す（`models` への依存は step 11 で外す）

※ pbxproj の行は、Xcode で消すか、行を手で消す。手で消すときは、同じ ID が他に残っていないことを確かめる。

## 確かめること

Swift を変えるので、`make run` し直す。

- iOS でビルドでき、今と同じく文字にできること
- `make build-ios` で作った ipa が、SenseVoice の分（約239MB）小さくなっていること
