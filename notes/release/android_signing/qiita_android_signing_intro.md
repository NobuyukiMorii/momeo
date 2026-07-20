## 概要

個人でスマホアプリを作っています。

Google Play に出す準備を進めていたら、「release 署名の設定が必要」という壁に当たりました。keystore、upload key、Play App Signing……初見だと用語が多くて身構えますが、やってみたら**役所の手続きみたいなもの**でした。「このアプリは間違いなく私が作ったものです」と証明するハンコを作って、ビルド時に押すようにする。それだけです。

同じところで止まっている人のために(あと未来の自分のために)、やったことを簡潔にまとめます。Flutter プロジェクト前提ですが、考え方は Android 共通です。

## そもそも署名ってなに？

- Google Play に出すアプリには「作った本人の証明」となる**電子署名**が必須
- ハンコの実体は **keystore** というパスワード付きのファイル
- Flutter の新規プロジェクトは「誰でも持っている練習用ハンコ(debug 署名)」のままなので、そのままでは提出できない

`android/app/build.gradle.kts` にこういう TODO が残っていたら、debug 署名のままです。

```kotlin
release {
    // TODO: Add your own signing config for the release build.
    signingConfig = signingConfigs.getByName("debug")
}
```

## やることは3ステップ

1. keytool で keystore(ハンコ)を作る
2. `key.properties`(ハンコの場所とパスワードのメモ)を作る
3. `build.gradle.kts` に「リリースビルド時はこのハンコを押す」設定を書く

## 📌 ステップ1：keystore を作る

```bash
mkdir -p ~/keystores/your-app

"/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" \
  -genkey -v \
  -keystore ~/keystores/your-app/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload

chmod 600 ~/keystores/your-app/upload-keystore.jks
```
keytool をフルパスで呼んでいるのは、macOS 標準の `/usr/bin/keytool` が Java Runtime なしでは動かななかったためです。Android Studio を入れていれば同梱の keytool がそのまま使えます。

実行すると対話形式でパスワードと識別情報を聞かれます。姓名・組織などは何を入れてもよく、ストアに表示されることもありません。**パスワードだけは絶対に忘れないように**保管してください。

## 📌 ステップ2：key.properties を作る

`android/key.properties` を作り、ハンコの場所とパスワードを書きます。

```properties
storePassword=<keystoreのパスワード>
keyPassword=<同じもの>
keyAlias=upload
storeFile=/Users/あなた/keystores/your-app/upload-keystore.jks
```

⚠️ パスワードが平文で入るので、**gitignore されていることを必ず確認**してください。最近の Flutter テンプレートは `android/.gitignore` に `key.properties` が最初から入っていますが、確認は一瞬です。

```bash
git check-ignore android/key.properties && echo OK
```

## 📌 ステップ3：build.gradle.kts を直す

`android/app/build.gradle.kts` に「key.properties を読んで release ビルドに署名する」設定を書きます。

```kotlin
import java.util.Properties
import java.io.FileInputStream

// release 署名の情報を key.properties（gitignore 済み）から読む
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
    buildTypes {
        release {
            // key.properties が無い環境でもビルドが通るよう debug 署名へフォールバック
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}
```

## 動作確認

署名設定が効いているかは signingReport で見られます。

```bash
cd android && ./gradlew :app:signingReport -q
```

release の欄に自分の keystore のパスと `Alias: upload` が出ていれば成功です。あとは `flutter build appbundle` で、Play に提出できる署名済み AAB ができます。

## 注意：バックアップだけは忘れずに

Play App Signing のおかげで鍵の紛失は致命傷ではなくなりましたが、リセット申請には数日かかり、その間リリース作業が止まります。

- パスワード → パスワードマネージャーへ
- keystore ファイル → 外部ドライブなどに控えを

この2つだけはやっておきましょう。