package jp.momeo

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    // 他のアプリが鳴っているかを Flutter から問い合わせるための橋渡し。
    //   ここで保持しておかないと不要物として回収され、通信が切れてしまうため、
    //   プロパティとして持ち続ける。
    private var audioSession: AudioSessionChannel? = null

    // OS 内蔵の文字起こし（SpeechRecognizer）を Flutter から使うための橋渡し（同じ理由で保持する）。
    private var speechRecognizer: SpeechRecognizerChannel? = null

    // Flutter エンジンの準備ができたタイミングで、橋渡しを有効化する。
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // リスニング画面のメモ一覧（OS の文字選択を使う TextView）を、Flutter の画面に埋め込めるようにする。
        flutterEngine.platformViewsController.registry.registerViewFactory(
            NativeMemoListFactory.VIEW_TYPE,
            NativeMemoListFactory(flutterEngine.dartExecutor.binaryMessenger),
        )
        audioSession = AudioSessionChannel(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        speechRecognizer = SpeechRecognizerChannel(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }
}
