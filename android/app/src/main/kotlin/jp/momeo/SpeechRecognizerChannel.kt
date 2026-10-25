package jp.momeo

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.LocaleList
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import kotlin.concurrent.thread

// ============================================================
// OS 内蔵の文字起こし（端末内の SpeechRecognizer）を Flutter から使うための橋渡し（Android 側）。
//
//   iOS 側（ios/Runner/SpeechTranscriberChannel.swift）と同じチャンネル名・メソッド名を使う。
//   VAD で区切った1発話ぶんの音（16kHz・Float32）を受け取り、パイプ経由で SpeechRecognizer に流して
//   テキストを返す。マイクは momeo の録音が持ったままなので、SpeechRecognizer にはマイクを使わせない。
//
//   言語は端末の「優先する言語」のうち、端末内モデルが入っている最初のものに固定する。
//   入っていなければダウンロードを頼み、downloading を返す（prepare の返事は iOS 側と同じ3つ）。
//
//   自分の音を渡す仕組み（EXTRA_AUDIO_SOURCE）が Android 13 からなので、それ未満は使わない。
//   SpeechRecognizer はメインスレッドでしか触れないため、ここの処理はすべてメインスレッドで動く。
// ============================================================
class SpeechRecognizerChannel(private val context: Context, messenger: BinaryMessenger) {

    companion object {
        private const val TAG = "SpeechRecognizer"
        private const val METHOD_CHANNEL = "jp.momeo/os_transcriber"
        private const val METHOD_PREPARE = "prepare"
        private const val METHOD_TRANSCRIBE = "transcribe"

        // prepare の返事（Dart の OsTranscriberState と一致させる）
        private const val STATE_READY = "ready"
        private const val STATE_DOWNLOADING = "downloading"
        private const val STATE_UNSUPPORTED = "unsupported"

        private const val INPUT_SAMPLE_RATE = 16000 // Flutter から届く音のサンプリングレート
        private const val TRANSCRIBE_TIMEOUT_MILLIS = 30_000L // 返事が来ないときに諦めるまでの時間
        private const val SILENCE_TO_END_MILLIS = 5_000L // これだけ無音が続くまで認識を終わらせない
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    // prepare が済むと埋まる
    private var recognizer: SpeechRecognizer? = null
    private var languageTag: String? = null

    init {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                METHOD_PREPARE -> prepare(result)
                METHOD_TRANSCRIBE -> {
                    val samples = call.arguments as? FloatArray
                    if (samples == null) {
                        result.error("bad_arguments", "音声サンプル（Float32List）が届いていません", null)
                    } else {
                        transcribe(samples, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // ---------------------------------
    // 使えるかの確認と、言語の決定
    // ---------------------------------
    private fun prepare(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            reply(result, STATE_UNSUPPORTED, "Android 13 未満のため使えません")
            return
        }
        if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
            reply(result, STATE_UNSUPPORTED, "この端末では端末内の音声認識が使えません")
            return
        }

        val onDeviceRecognizer = recognizer ?: SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        recognizer = onDeviceRecognizer

        val supportIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        onDeviceRecognizer.checkRecognitionSupport(
            supportIntent,
            context.mainExecutor,
            object : RecognitionSupportCallback {
                override fun onSupportResult(support: RecognitionSupport) {
                    chooseLanguage(onDeviceRecognizer, support, result)
                }

                // 一時的な失敗もあるので、使えないとは決めずに失敗として返す（Dart 側が再試行する）
                override fun onError(error: Int) {
                    result.error("support_check_failed", "対応言語を確かめられませんでした（error: $error）", null)
                }
            },
        )
    }

    // 優先する言語を上から見て、端末内モデルが入っている最初の言語を選ぶ
    private fun chooseLanguage(
        onDeviceRecognizer: SpeechRecognizer,
        support: RecognitionSupport,
        result: MethodChannel.Result,
    ) {
        val preferredLocales = LocaleList.getDefault()
        val installedTags = support.installedOnDeviceLanguages
        val pendingTags = support.pendingOnDeviceLanguages
        val downloadableTags = support.supportedOnDeviceLanguages

        for (index in 0 until preferredLocales.size()) {
            val preferredLocale = preferredLocales[index]

            val installedTag = findMatchingTag(preferredLocale, installedTags)
            if (installedTag != null) {
                languageTag = installedTag
                reply(result, STATE_READY, "locale: $installedTag / installed: $installedTags")
                return
            }

            // ダウンロード待ち・進行中の言語は、頼み直さずに終わるのを待つ
            val pendingTag = findMatchingTag(preferredLocale, pendingTags)
            if (pendingTag != null) {
                reply(result, STATE_DOWNLOADING, "$pendingTag のモデルをダウンロード中です")
                return
            }

            // 対応はしているがモデルが入っていない言語は、ダウンロードを頼む
            val downloadableTag = findMatchingTag(preferredLocale, downloadableTags)
            if (downloadableTag != null) {
                val downloadIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                    .putExtra(RecognizerIntent.EXTRA_LANGUAGE, downloadableTag)
                onDeviceRecognizer.triggerModelDownload(downloadIntent)
                reply(result, STATE_DOWNLOADING, "$downloadableTag のモデルのダウンロードを頼みました")
                return
            }
        }

        reply(
            result,
            STATE_UNSUPPORTED,
            "優先する言語（${preferredLocales.toLanguageTags()}）のどれにも対応していません" +
                "（installed: $installedTags）",
        )
    }

    // 言語と地域が一致するものを優先し、無ければ言語だけ一致するものを返す
    private fun findMatchingTag(preferredLocale: Locale, candidateTags: List<String>): String? {
        val exactMatch = candidateTags.firstOrNull { tag ->
            Locale.forLanguageTag(tag) == preferredLocale
        }
        if (exactMatch != null) return exactMatch

        return candidateTags.firstOrNull { tag ->
            Locale.forLanguageTag(tag).language == preferredLocale.language
        }
    }

    // ---------------------------------
    // 1発話ぶんの文字化
    //   音をパイプに書き込み、書き終わりを「入力の終わり」として SpeechRecognizer に認識させる
    // ---------------------------------
    private fun transcribe(samples: FloatArray, result: MethodChannel.Result) {
        val onDeviceRecognizer = recognizer
        val tag = languageTag
        if (onDeviceRecognizer == null || tag == null) {
            result.error("not_prepared", "prepare が済んでいません", null)
            return
        }

        val (readSide, writeSide) = ParcelFileDescriptor.createPipe()
        val session = TranscribeSession(result, readSide)

        onDeviceRecognizer.setRecognitionListener(session)
        onDeviceRecognizer.startListening(makeRecognizeIntent(tag, readSide))

        // パイプへの書き込みは、読み手が追いつくまで待たされるので別スレッドで行う
        val pcm16Bytes = toPcm16Bytes(samples)
        thread(name = "speech-recognizer-writer") {
            try {
                ParcelFileDescriptor.AutoCloseOutputStream(writeSide).use { output ->
                    output.write(pcm16Bytes)
                }
            } catch (error: IOException) {
                Log.w(TAG, "音声をパイプに書き込めませんでした: $error")
            }
        }

        // 返事が来ないまま次の発話が詰まらないよう、一定時間で諦める
        mainHandler.postDelayed({
            if (session.finish()) {
                onDeviceRecognizer.cancel()
                result.error("timeout", "SpeechRecognizer から返事がありませんでした", null)
            }
        }, TRANSCRIBE_TIMEOUT_MILLIS)
    }

    private fun makeRecognizeIntent(tag: String, audioSource: ParcelFileDescriptor): Intent {
        return Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, tag)
            .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            // マイクの代わりに、パイプから流す音を認識させる
            .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, audioSource)
            .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, INPUT_SAMPLE_RATE)
            .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            // 途中の無音で止めず、流した音の終わりまで認識させる（結果は区間ごとに届く）
            .putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION, RecognizerIntent.EXTRA_AUDIO_SOURCE)
            // 区間ごとの結果が届かない端末向けに、momeo の区切り（3秒の無音）より短い無音では終わらせない
            .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, SILENCE_TO_END_MILLIS)
            .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, SILENCE_TO_END_MILLIS)
            // 句読点などを整えてもらう
            .putExtra(RecognizerIntent.EXTRA_ENABLE_FORMATTING, RecognizerIntent.FORMATTING_OPTIMIZE_QUALITY)
    }

    // [-1, 1] の Float32 を PCM16 little-endian へ
    private fun toPcm16Bytes(samples: FloatArray): ByteArray {
        val buffer = ByteBuffer.allocate(samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (sample in samples) {
            val clamped = sample.coerceIn(-1f, 1f)
            buffer.putShort((clamped * Short.MAX_VALUE).toInt().toShort())
        }
        return buffer.array()
    }

    private fun reply(result: MethodChannel.Result, state: String, detail: String) {
        result.success(mapOf("state" to state, "detail" to detail))
    }

    // ---------------------------------
    // 1回の文字化で届く結果を集めて、1回だけ返事をする係
    // ---------------------------------
    private inner class TranscribeSession(
        private val result: MethodChannel.Result,
        private val readSide: ParcelFileDescriptor,
    ) : RecognitionListener {

        private val segmentTexts = mutableListOf<String>()
        private var finished = false

        // まだ返事をしていなければ終わった印を付けて true を返す（返事を1回に限るため）
        fun finish(): Boolean {
            if (finished) return false
            finished = true
            try {
                readSide.close()
            } catch (_: IOException) {
                // 既に閉じていれば何もしない
            }
            return true
        }

        // 区間ごとの結果（途中の無音で区切られた単位）
        override fun onSegmentResults(segmentResults: Bundle) {
            firstCandidate(segmentResults)?.let { segmentTexts.add(it) }
        }

        // 流した音の終わりまで認識し終えた
        override fun onEndOfSegmentedSession() {
            if (finish()) result.success(segmentTexts.joinToString(""))
        }

        // 区切りなしで終わった場合の結果
        override fun onResults(results: Bundle) {
            firstCandidate(results)?.let { segmentTexts.add(it) }
            if (finish()) result.success(segmentTexts.joinToString(""))
        }

        override fun onError(error: Int) {
            if (!finish()) return
            // 声が聞き取れなかっただけなら、空のテキストとして返す
            if (error == SpeechRecognizer.ERROR_NO_MATCH || error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
                result.success(segmentTexts.joinToString(""))
            } else {
                result.error("recognizer_error", "SpeechRecognizer のエラー（error: $error）", null)
            }
        }

        private fun firstCandidate(bundle: Bundle): String? {
            return bundle.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
        }

        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}

        override fun onPartialResults(partialResults: Bundle?) {}

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }
}
