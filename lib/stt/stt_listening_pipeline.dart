import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:record/record.dart';

import 'package:momeo/stt/stt_audio_worker.dart';

// ============================================================
// リスニングの録音パイプライン（録音 → 音声 isolate → 通知）
//
//   マイクの音を連続キャプチャして音声 isolate へ流し、そこから戻ってくる
//   「発話中フラグ・音量・確定テキスト」をコールバックへ配る。
//   区切りと文字化は音声 isolate の担当で、ここでは一切行わない。
//
//   所有するのは AudioRecorder だけ。SttAudioWorker は借り物で、
//   dispose では区切り役の解放だけを頼み、認識器には触れない。
// ============================================================

const int _kSampleRate = 16000; // 録音のサンプリングレート（VAD・NeMo の前提）

class SttListeningPipeline {
  SttListeningPipeline({
    required SttAudioWorker worker,
    required String sileroPath,
    required this.onTranscribed,
    this.onSpeechActiveChanged,
    this.onLevelChanged,
  })  : _worker = worker,
        _sileroPath = sileroPath;

  final SttAudioWorker _worker;
  final String _sileroPath;

  // 1発話ぶんの文字化が終わるたびに呼ばれる通知先
  final void Function(SttTranscribed result) onTranscribed;

  // 発話中かどうかが切り替わるたびに呼ばれる通知先（任意）
  final void Function(bool isActive)? onSpeechActiveChanged;

  // マイク音量メーター用に、チャンクごとのピーク音量を渡す通知先（任意）
  final void Function(double level)? onLevelChanged;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<SttAudioEvent>? _eventSubscription;

  bool _running = false;

  // ---------------------------------
  // リスニングの開始 / 停止
  // ---------------------------------

  Future<void> start() async {
    if (_running) return;

    // 権限フローで許可済みの前提だが、念のため確認する
    final granted = await _recorder.hasPermission();
    if (!granted) {
      throw StateError('マイクの利用が許可されていません（RECORD_AUDIO）');
    }

    await _worker.startListening(sileroPath: _sileroPath);

    // 中断（着信・他アプリのマイク奪取）からの復帰設定
    //   既定の pause は自動停止・手動再開のため、再開処理が無いと止まったまま戻らない。
    //   pauseResume は mixWithOthers との併用が必要（record のドキュメント）。
    //   allowHapticsAndSystemSoundsDuringRecording は着信音だけでの中断を防ぐ。
    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _kSampleRate,
      numChannels: 1,
      audioInterruption: AudioInterruptionMode.pauseResume,
      iosConfig: IosRecordConfig(
        categoryOptions: [
          IosAudioCategoryOption.mixWithOthers,
          IosAudioCategoryOption.defaultToSpeaker,
          IosAudioCategoryOption.allowBluetooth,
          IosAudioCategoryOption.allowBluetoothA2DP,
        ],
        allowHapticsAndSystemSoundsDuringRecording: true,
      ),
    );
    final stream = await _recorder.startStream(config);

    // 通知の購読を先に始めてから音声を流す（順番が逆だと最初の通知を取りこぼす）
    _eventSubscription = _worker.events.listen(
      _onWorkerEvent,
      onError: (Object error) => debugPrint('[sttPipeline] 音声 isolate のエラー: $error'),
    );
    _audioSubscription = stream.listen(
      _worker.pushAudio,
      onError: (Object error) => debugPrint('[sttPipeline] 録音ストリームのエラー: $error'),
    );
    _running = true;
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    await _audioSubscription?.cancel();
    _audioSubscription = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // 停止時の例外は致命的でないため無視
    }

    // 末尾に残った発話を押し出す。確定テキストは通知で戻ってくるため、
    // それを受け取り終えてから購読を切る
    try {
      await _worker.stopListening();
    } catch (error) {
      debugPrint('[sttPipeline] 末尾の発話を確定できませんでした: $error');
    }
    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  // ---------------------------------
  // 音声 isolate からの通知を配る
  // ---------------------------------

  void _onWorkerEvent(SttAudioEvent event) {
    switch (event) {
      case SttSpeechActiveChanged(:final isActive):
        onSpeechActiveChanged?.call(isActive);
      case SttMicLevelMeasured(:final level):
        onLevelChanged?.call(level);
      case SttTranscribed():
        if (kDebugMode) {
          debugPrint(
            '[sttPipeline] 発話 ${event.durationSec.toStringAsFixed(1)}s'
            ' → 転写 ${event.elapsedMs}ms'
            ' → 「${event.text}」',
          );
        }
        onTranscribed(event);
    }
  }

  // ---------------------------------
  // 後始末（借り物の認識器には触らない）
  // ---------------------------------

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
    try {
      await _worker.releaseListening();
    } catch (_) {
      // isolate が既に終わっている場合は解放するものが無い
    }
  }
}
