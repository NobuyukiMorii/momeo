# Step 11 【共通】モデルの取得スクリプトを消す

## 目的

SenseVoice を手元（`.dev_models/`）へダウンロードするスクリプトと、その呼び出しを消す。

`make run`・`make build-ios`・`make build-android` の前に、約239MB の確かめやダウンロードが走らなくなる。


| 項目 | 今 | この step の後 |
| --- | --- | --- |
| `make run` などの前 | `make models` が走り、SenseVoice が揃っているかを確かめる（無ければダウンロード） | 走らない |
| `make models` | ある | 無い |
| `.gitignore` | SenseVoice の置き場所を無視する行がある | 無い |


## やること

### 消すもの

| ファイル | 中身 |
| --- | --- |
| `scripts/download_stt_model.sh` | SenseVoice を `.dev_models/` へダウンロードするスクリプト |
| `scripts/lib/stt_model_constants.sh` | 取得元・ファイル名・正しいバイト数 |


### 直すもの

- `Makefile`
  - `models` のターゲットと、`run`・`build-ios`・`build-android` の `models` への依存を消す
  - 冒頭の使い方の説明（`make models` の行と、「モデルを揃えてから」の言い回し）を直す
  - `.PHONY` から `models` を外す
- `.gitignore`
  - SenseVoice の置き場所の行（`/.dev_models/`、`/ios/Runner/Models/...`、`/android/stt_models/...`）と、その説明コメントを消す

※ 手元の `.dev_models/` は git の外にあるので、必要なら手で消す（`rm -rf .dev_models`）。

## 確かめること

- `make help` の説明に、モデルの話が残っていないこと
- `make run d=<端末>` が、モデルのダウンロードや確かめをせずに起動まで進むこと（iOS・Android の両方）
- `grep -rn "download_stt_model\|stt_model_constants\|dev_models" .` で、残っている参照が notes の経緯の文書だけであること
