# Android release 署名の整備

Google Play 提出に必要な release 署名(upload keystore)の仕組みと、実装内容をまとめる。
[store_release_plan.md](../store_release_plan.md) の Phase 1「Android release 署名の整備」に対応する。

## そもそも署名とは何か(前提知識)

Google Play にアプリを出すには「これは間違いなく本人が作ったアプリである」と
証明する **ハンコ(電子署名)** をビルドに押す必要がある。

- ハンコの実体は **keystore** というファイル(パスワード付き)
- 現状は開発用の「誰でも持っている練習用ハンコ(debug 署名)」で代用しており、
  このままでは Google Play に提出できない
- `android/app/build.gradle.kts` に Flutter テンプレートの TODO が残ったままの状態:

```kotlin
buildTypes {
    release {
        // TODO: Add your own signing config for the release build.
        signingConfig = signingConfigs.getByName("debug")
    }
}
```

## Play App Signing の仕組み(鍵が2つある理由)

Google Play は**署名鍵を2段構え**にしている。AAB で提出する新規アプリでは自動的に
この方式になり、こちらで特別な作業は不要。

| 鍵 | 持ち主 | 役割 |
|---|---|---|
| **app signing key**(署名鍵) | Google が金庫で保管 | ユーザー端末に届く APK に押される本物のハンコ |
| **upload key**(アップロード鍵) | 自分が保管 | Play にアップロードする時の本人確認用。今回作るのはこれ |

この分離のおかげで、upload key を紛失・漏洩しても Play Console から
**リセットを申請すれば再発行できる**(数日かかる)。
本物の署名鍵は Google が持っているので、アプリの更新が永久に不可能になる事故が起きない。

## 実装内容(3ステップ)

### Step 1: upload keystore を作る(手作業・1回だけ)

`keytool` コマンドで keystore ファイルを生成する。

```bash
mkdir -p ~/keystores/momeo

"/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" \
  -genkey -v \
  -keystore ~/keystores/momeo/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload

# 本人以外読めないように絞る
chmod 600 ~/keystores/momeo/upload-keystore.jks
```

- `/usr/bin/keytool` は Java Runtime が無くて動かないため、Android Studio 同梱の
  keytool をフルパスで使う
- 保存先は `~/keystores/<アプリ名>/` に統一する。リポジトリ外なので誤コミットの
  余地がなく、今後アプリが増えても `~/keystores` を丸ごとバックアップするだけで済む
  - `~/.android` は不採用: エミュレータのキャッシュなどツール管理の領域で、
    トラブル時に丸ごと消す操作が定番のため、大事な鍵の置き場所に向かない
  - `~/Documents` は不採用: iCloud 同期で意図せずクラウドに上がり得る。
    バックアップは明示的に取る方が管理がはっきりする
- 実行すると対話形式でパスワードと識別情報(氏名・組織など)を聞かれる。
  識別情報は何でもよく、ストアに表示されることもない
- `-validity 10000`(約27年)は Play の要件(2033年10月以降まで有効)を満たす慣例値

### Step 2: key.properties を作る(手作業・1回だけ)

「ハンコの置き場所とパスワードのメモ」にあたる設定ファイルを
`android/key.properties` に作る。

```properties
storePassword=<keystore作成時のパスワード>
keyPassword=<同上(通常同じ)>
keyAlias=upload
storeFile=/Users/mory/keystores/momeo/upload-keystore.jks
```

`android/.gitignore` が `key.properties` / `**/*.jks` / `**/*.keystore` を
除外済みのため、コミットされない(整備済み・追記不要)。

### Step 3: build.gradle.kts の signingConfig 修正(コード変更)

「リリースビルド時は Step 2 のメモを読んで Step 1 のハンコを押す」設定を
`android/app/build.gradle.kts` に書く。変更するのはこのファイルだけ。

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
            // key.properties が無い環境でも `flutter run --release` が通るよう debug 署名へフォールバック
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}
```

署名設定が効いているかは `./gradlew :app:signingReport` で確認できる
(release variant に upload keystore のパスと alias が表示されれば OK)。

## 完了後にどうなるか

- いつもの `make build-android` を打つだけで release 署名済みの AAB ができる
  (Makefile の変更は不要。`flutter build appbundle` が signingConfig を自動で使う)
- Play Console に最初の AAB をアップロードした時点で Play App Signing が有効になる
- store_release_plan.md の次項目「リリースビルドの実機確認」にそのまま進める
  (実機確認だけなら `flutter build apk --release` の方が手軽)

## 注意点

- **keystore とパスワードは必ずバックアップする**。紛失しても再発行はできるが、
  リセット申請で数日リリース作業が止まる。パスワードはパスワードマネージャーへ、
  keystore ファイル自体も別の場所に控えを置く
- keystore・パスワードをリポジトリ・チャット・クラウドの公開領域に置かない
- 普段の開発(`flutter run` や debug ビルド)には一切影響しない
