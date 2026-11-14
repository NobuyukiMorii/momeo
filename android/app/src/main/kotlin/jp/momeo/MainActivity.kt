package jp.momeo

import android.os.Bundle
import android.view.View
import android.view.ViewTreeObserver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    // 他のアプリが鳴っているかを Flutter から問い合わせるための橋渡し。
    //   ここで保持しておかないと不要物として回収され、通信が切れてしまうため、
    //   プロパティとして持ち続ける。
    private var audioSession: AudioSessionChannel? = null

    // OS 内蔵の文字起こし（SpeechRecognizer）を Flutter から使うための橋渡し（同じ理由で保持する）。
    private var speechRecognizer: SpeechRecognizerChannel? = null

    // Flutter が最初の画面を描き終えたか（それまで OS の起動画面を残しておく）
    private var isFlutterUiDisplayed = false

    // ---------------------------------
    // OS の起動画面の引き継ぎ
    // ---------------------------------
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Flutter が描き終わるまで画面の更新を止め、起動画面（録音ボタン）を出したままにする
        val content = findViewById<View>(android.R.id.content)
        content.viewTreeObserver.addOnPreDrawListener(object : ViewTreeObserver.OnPreDrawListener {
            override fun onPreDraw(): Boolean {
                if (!isFlutterUiDisplayed) return false
                content.viewTreeObserver.removeOnPreDrawListener(this)
                return true
            }
        })

        // 起動画面はフェードさせずに即座に外す（下に同じ録音ボタンが描かれているので、入れ替わりが見えない）
        splashScreen.setOnExitAnimationListener { splashView -> splashView.remove() }
    }

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        isFlutterUiDisplayed = true
    }

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
