import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

// ============================================================
// VAD のモデル（silero）の「住所を返す窓口」
//
//   sherpa は実ファイルの「住所（パス）」からしかモデルを読めない。
//   silero は Flutter アセットとして同梱しているので、端末の書き込み領域へコピーして実パスを作る。
// ============================================================

// silero VAD（アセット同梱 → 端末コピー）
//   入手元: https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx
//   リポジトリにコミット済み（git が中身を固定）。更新するときは assets/models/silero_vad.onnx を差し替える。
const String _kSileroAssetPath = 'assets/models/silero_vad.onnx';
const String _kSileroFileName = 'silero_vad.onnx';

class SttModelProvisioner {
  // silero をアセットから端末の書き込み領域へコピーし、その実パスを返す（コピー済みなら何もしない）
  Future<String> ensureSilero() async {
    final supportDir = await getApplicationSupportDirectory();
    final file = File('${supportDir.path}/$_kSileroFileName');
    if (!await file.exists()) {
      final data = await rootBundle.load(_kSileroAssetPath);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
  }
}
