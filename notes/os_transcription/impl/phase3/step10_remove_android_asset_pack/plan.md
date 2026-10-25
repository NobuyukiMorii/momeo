# Step 10 【Android】Play の自動ダウンロードを消す

## 目的

Android で SenseVoice を配っている、Play の自動ダウンロード（fast-follow のアセットパック）を消す。

インストールの直後に約239MB をダウンロードすることが無くなる。

動きは変えない（step 8 で、Dart から呼ばれなくなっている）。


| 項目 | 今 | この step の後 |
| --- | --- | --- |
| AAB（Google Play に渡す形）に入っているもの | アプリ本体と、アセットパック `stt_models`（SenseVoice） | アプリ本体だけ |
| 窓口 `AssetPackDeliveryChannel` | 登録されている（呼ばれていない） | 無い |
| `INTERNET` 権限 | `asset-delivery` ライブラリが自動で足している | 無くなる（ほかに足しているものが無ければ） |
| `make run`（debug） | 起動の前に、adb で端末へモデルを置く | 置かない |
| `make run`（release） | AAB を作り、bundletool で端末に入る形にして入れる | `flutter run --release` で入れる |


## やること

### 消すもの

| ファイル | 中身 |
| --- | --- |
| `android/stt_models/`（フォルダごと） | アセットパックのモジュール |
| `android/app/src/main/kotlin/jp/momeo/AssetPackDeliveryChannel.kt` | ダウンロードの窓口 |
| `scripts/place_android_device_models.sh` | 開発中に adb で端末へモデルを置くスクリプト |
| `scripts/place_android_pack_models.sh` | AAB を作る前に、アセットパックへモデルを置くスクリプト |


### 直すもの

- `android/settings.gradle.kts`：`include(":stt_models")` を消す
- `android/app/build.gradle.kts`：`assetPacks += ":stt_models"` と、`com.google.android.play:asset-delivery` の依存を消す
- `android/app/src/main/kotlin/jp/momeo/MainActivity.kt`：`assetPackDelivery` の保持と作成を消す
- `scripts/run_on_device.sh`
  - 「Android の release は本番経路で動かす」の分岐を消し、Android の release も `flutter run --release` にする
  - `place_android_device_models.sh` の呼び出しを消す
  - 「手置きできないアプリが入っているため、アンインストールします」の処理（モデルを手置きするために debug ビルドを先に入れていた部分）が要らなくなるかを確かめ、要らなければ消す
- `scripts/install_android_bundle.sh`
  - アセットパックのために AAB を経由していたなら、使われなくなるので消す。ほかに使い道があれば残す
- `Makefile`
  - `build-android` の `place_android_pack_models.sh` を消す（`models` への依存は step 11 で外す）

※ `INTERNET` 権限が本当に無くなったかは、release の AAB の manifest で確かめる（ほかのプラグインが足している場合は残る。そのときは残してよい）。

## 確かめること

Kotlin と Gradle の設定を変えるので、`make run` し直す。

- Android で debug・release ともビルドでき、今と同じく文字にできること
- `make build-android` の AAB に `stt_models` が入っていないこと
- `INTERNET` 権限の有無（上の※）
