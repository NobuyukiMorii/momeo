import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// release 署名の情報を key.properties（gitignore 済み）から読む
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "jp.momeo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // NeMo（625MB）を運ぶ fast-follow アセットパックを、このアプリのビルドに紐づける。
    // 実体は :nemo_models モジュール（android/nemo_models/）。これで AAB に同梱される。
    assetPacks += ":nemo_models"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications（iOS の録音中通知に使用）が要求する
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "jp.momeo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

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

dependencies {
    // Play Asset Delivery のランタイム（AssetPackManager を含む）。
    // アセットパックの「DL状態の取得・進捗監視・完了後の実パス取得・再試行」に使う。
    implementation("com.google.android.play:asset-delivery:2.2.2")

    // isCoreLibraryDesugaringEnabled とペアで要る実体
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
