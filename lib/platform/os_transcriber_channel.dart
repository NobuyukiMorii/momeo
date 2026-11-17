import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

// ============================================================
// OS 内蔵の文字起こしの窓口
//
//   iOS は SpeechTranscriber、Android は端末内の SpeechRecognizer が、同じチャンネル名・メソッド名で応える。
//   VAD で区切った1発話ぶんの音（16kHz・Float32）を渡すと、テキストが返る。
//   言語のモデルのダウンロードが終わると、ネイティブから downloadFinished が届く。
// ============================================================

class OsTranscriberChannel {
  static const MethodChannel _channel = MethodChannel(
    'jp.momeo/os_transcriber',
  );

  // ---------------------------------
  // 待ち画面の確認用: 言語のモデルのダウンロード中のふり
  //   --dart-define=FAKE_LANGUAGE_DOWNLOAD_SECONDS=10 でビルドしたときだけ、
  //   最初の問い合わせから指定秒数のあいだ、OS の返事を「ダウンロード中」に差し替える（0 なら何もしない）
  //   進み具合も、経過時間に合わせて 0〜100% に増えていくふりをする。
  //   --dart-define=FAKE_LANGUAGE_DOWNLOAD_HIDE_PROGRESS=true を足すと、進み具合は「分からない」のままにする
  //   （Android 13 のように、ドットのまま待つ見え方の確認用）
  // ---------------------------------
  static const _fakeDownloadSeconds = int.fromEnvironment(
    'FAKE_LANGUAGE_DOWNLOAD_SECONDS',
  );
  static const _fakeHidesProgress = bool.fromEnvironment(
    'FAKE_LANGUAGE_DOWNLOAD_HIDE_PROGRESS',
  );
  static final _sinceFirstPrepare = Stopwatch();

  // ---------------------------------
  // 言語のモデルのダウンロードが終わった知らせ
  //   iOS と Android 14 以降で、momeo が頼んだダウンロードが終わったときに届く
  //   （Android 13 や、momeo が頼んでいないダウンロードでは届かない）
  // ---------------------------------
  static final _downloadFinishedController = StreamController<void>.broadcast(
    onListen: _listenNativeCalls,
  );
  static Stream<void> get downloadFinished =>
      _downloadFinishedController.stream;

  static void _listenNativeCalls() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'downloadFinished') {
        _downloadFinishedController.add(null);
      }
    });
  }

  // 使えるかを確かめる。言語のモデルが端末に無ければ、OS にダウンロードを頼む
  static Future<OsTranscriberStatus> prepare() async {
    if (!_sinceFirstPrepare.isRunning) _startFakeDownloadClock();

    final reply = await _channel.invokeMapMethod<String, Object?>('prepare');
    final status = OsTranscriberStatus(
      state: OsTranscriberState.fromName(reply?['state']),
      detail: '${reply?['detail'] ?? '-'}',
    );

    // ふりの期間中は、OS の本当の返事の代わりに「ダウンロード中」を返す
    if (_isFakingDownload) {
      return OsTranscriberStatus(
        state: OsTranscriberState.downloading,
        detail: 'ダウンロード中のふり（本当の返事: ${status.state.name}）',
      );
    }
    return status;
  }

  // 言語のモデルのダウンロードの進み具合（0.0〜1.0）。分からなければ null
  //   Android 13 や、OS からまだ知らせが届いていないときは null になる
  static Future<double?> downloadProgress() async {
    if (_isFakingDownload) return _fakeDownloadProgress();

    try {
      return await _channel.invokeMethod<double>('downloadProgress');
    } on PlatformException {
      return null;
    }
  }

  // ふりの時計を動かし始め、ふりの期間が終わったら本物と同じく「終わった知らせ」を出す
  static void _startFakeDownloadClock() {
    _sinceFirstPrepare.start();
    if (_fakeDownloadSeconds <= 0 || _fakeHidesProgress) return;
    Timer(
      const Duration(seconds: _fakeDownloadSeconds),
      () => _downloadFinishedController.add(null),
    );
  }

  static bool get _isFakingDownload =>
      _sinceFirstPrepare.isRunning &&
      _sinceFirstPrepare.elapsed.inSeconds < _fakeDownloadSeconds;

  static double? _fakeDownloadProgress() {
    if (_fakeHidesProgress) return null;
    return _sinceFirstPrepare.elapsedMilliseconds / (_fakeDownloadSeconds * 1000);
  }

  // 1発話ぶんの音を文字化する
  static Future<String> transcribe(Float32List samples) async {
    final text = await _channel.invokeMethod<String>('transcribe', samples);
    return text ?? '';
  }
}

// prepare の返事
enum OsTranscriberState {
  ready, // すぐ使える
  downloading, // 対応している言語だが、言語のモデルのダウンロードが終わっていない
  unsupported; // 端末か言語が対応していない

  // ネイティブから届いた名前を読む。知らない名前は使えない扱いにする
  static OsTranscriberState fromName(Object? name) {
    return OsTranscriberState.values.firstWhere(
      (state) => state.name == name,
      orElse: () => OsTranscriberState.unsupported,
    );
  }
}

class OsTranscriberStatus {
  const OsTranscriberStatus({required this.state, required this.detail});

  final OsTranscriberState state;
  final String detail; // 使える言語や、使えない理由の説明
}
