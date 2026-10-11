package jp.momeo

import android.content.Context
import android.media.AudioManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

// ============================================================
// 他のアプリの音に録音を合わせるための橋渡し（Android 側）。
//
//   iOS 側（ios/Runner/AudioSessionChannel.swift）と同じチャンネル名を使う。
//   Android は録音が他のアプリの音をこもらせないため、ここで扱うのは
//   「他のアプリが鳴っているか」の問い合わせだけ。
//
//   ※ チャンネル名・メソッド名は、Dart 側（lib/platform/audio_session_channel.dart）と
//     必ず一致させること。
// ============================================================
class AudioSessionChannel(context: Context, messenger: BinaryMessenger) {

    companion object {
        private const val METHOD_CHANNEL = "jp.momeo/audio_session"
        private const val METHOD_IS_OTHER_AUDIO_PLAYING = "isOtherAudioPlaying"
    }

    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    init {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // 音楽・動画などのメディア再生が鳴っているか（通知音や着信音は含まない）
                METHOD_IS_OTHER_AUDIO_PLAYING -> result.success(audioManager.isMusicActive)
                else -> result.notImplemented()
            }
        }
    }
}
