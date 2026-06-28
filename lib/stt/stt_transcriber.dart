import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

// ============================================================
// 発話チャンク（区切った音声）を日本語テキストに変換する部品（文字化の核）
//
//   入力: VAD（Step 5）が区切った1発話分の音声サンプル（Float32 / [-1,1] / 16kHz）
//   出力: 日本語テキスト
//
//   使うモデルは NeMo（CTC 方式）。住所（実パス）は Step 6 の窓口
//   （SttModelProvisioner）から受け取る前提で、ここでは「パスをもらって文字にする」
//   ことだけを担当する。UI も録音も持たない。
//
//   ■ 文字化の流れ
//   ① パスから認識器（OfflineRecognizer）を1つ作る（CTC 方式 = nemoCtc を指定）
//   ② 1発話ごとに stream を作り、音声を渡して decode → テキストを取り出す
//   ③ 使い終わったら認識器を解放する（dispose）
//
//   ※ 呼び出す前に sherpa.initBindings() を済ませておくこと（ネイティブ初期化）。
// ============================================================

const int _kSampleRate = 16000; // NeMo / VAD が前提とする 16kHz

class SttTranscriber {
  SttTranscriber._(this._recognizer);

  final sherpa.OfflineRecognizer _recognizer;

  // ---------------------------------
  // NeMo の実パス（本体・tokens）から認識器を作る
  //   modelPath  : model.int8.onnx の実パス（音 → 番号）
  //   tokensPath : tokens.txt の実パス（番号 → 文字）
  //   ※ この2つは必ずペア。Step 6 の窓口が返す住所をそのまま渡す。
  // ---------------------------------
  factory SttTranscriber.create({
    required String modelPath,
    required String tokensPath,
  }) {
    final config = sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        // NeMo は CTC 方式。この枠にモデル本体のパスを入れることで
        // 「CTC 方式のモデルとして読む」ことが決まる。
        nemoCtc: sherpa.OfflineNemoEncDecCtcModelConfig(model: modelPath),
        tokens: tokensPath,
        numThreads: 1,
        // 開発中（デバッグビルド）だけ sherpa の内部ログを出す。
        // リリースビルドでは kDebugMode が false になり自動的に静かになる。
        debug: kDebugMode,
      ),
    );
    return SttTranscriber._(sherpa.OfflineRecognizer(config));
  }

  // ---------------------------------
  // 1発話分の音声サンプルを日本語テキストに変換する
  //   samples: Float32 / [-1,1] / 16kHz（VAD の SpeechSegment.samples をそのまま渡せる）
  //   発話ごとに stream を使い捨てる（OfflineRecognizer の作法）。
  // ---------------------------------
  String transcribe(Float32List samples) {
    final stream = _recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: _kSampleRate);
      _recognizer.decode(stream);
      return _recognizer.getResult(stream).text;
    } finally {
      // 成功・失敗にかかわらず stream は必ず解放する（メモリリーク防止）
      stream.free();
    }
  }

  // ---------------------------------
  // 後始末：認識器をメモリから解放する
  //   （VAD が dispose で free() するのと同じ作法）
  // ---------------------------------
  void dispose() {
    _recognizer.free();
  }
}
