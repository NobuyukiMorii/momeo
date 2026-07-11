package jp.momeo

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    // アセットパックの自動DLを Flutter から操作するための橋渡し。
    //   ここで保持しておかないと不要物として回収され、通信が切れてしまうため、
    //   プロパティとして持ち続ける。
    private var assetPackDelivery: AssetPackDeliveryChannel? = null

    // Flutter エンジンの準備ができたタイミングで、橋渡しを有効化する。
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // applicationContext を渡す（アプリ全体で1つの AssetPackManager を使うため）。
        assetPackDelivery = AssetPackDeliveryChannel(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }
}
