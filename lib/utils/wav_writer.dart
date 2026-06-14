import 'dart:io';
import 'dart:typed_data';

// =====================================================================
// WavWriter — float PCM サンプルを 16bit PCM の WAV ファイルに書き出す
//
// VAD（vad パッケージ）が返す発話サンプルは List<double>（値域 -1.0〜1.0・
// 16kHz・モノラル）。一方 whisper_flutter_new の転写入力は WAV ファイルパス。
// この差を埋めるため、サンプルを WAV(16bit PCM) に変換して保存する。
// =====================================================================
class WavWriter {
  // ---------------------------------
  // WAV の固定仕様（VAD の出力に合わせる）
  // ---------------------------------
  static const int _sampleRate = 16000; // 16kHz
  static const int _numChannels = 1; // モノラル
  static const int _bitsPerSample = 16; // 16bit PCM

  // ヘッダのバイト数（PCM の WAV は 44 バイト固定）
  static const int _headerSize = 44;

  // ---------------------------------
  // float サンプルを WAV ファイルとして書き出し、保存先の File を返す
  // ---------------------------------
  static Future<File> writeToFile({
    required List<double> samples,
    required String filePath,
  }) async {
    final bytes = _buildWavBytes(samples);
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  // ---------------------------------
  // WAV バイト列（44バイトヘッダ + PCMデータ）を組み立てる
  // ---------------------------------
  static Uint8List _buildWavBytes(List<double> samples) {
    final int dataLength = samples.length * (_bitsPerSample ~/ 8);

    final builder = BytesBuilder();
    builder.add(_buildHeader(dataLength));
    builder.add(_floatTo16BitPcm(samples));
    return builder.toBytes();
  }

  // ---------------------------------
  // WAV ヘッダ（RIFF / fmt / data の各チャンク）を作る
  // ---------------------------------
  static Uint8List _buildHeader(int dataLength) {
    final header = ByteData(_headerSize);

    // RIFF チャンク
    _writeAscii(header, 0, 'RIFF');
    header.setUint32(4, _headerSize - 8 + dataLength, Endian.little); // 以降のサイズ
    _writeAscii(header, 8, 'WAVE');

    // fmt サブチャンク
    _writeAscii(header, 12, 'fmt ');
    header.setUint32(16, 16, Endian.little); // fmt チャンクのサイズ（PCM は 16）
    header.setUint16(20, 1, Endian.little); // フォーマット（PCM = 1）
    header.setUint16(22, _numChannels, Endian.little);
    header.setUint32(24, _sampleRate, Endian.little);
    final int byteRate = _sampleRate * _numChannels * (_bitsPerSample ~/ 8);
    header.setUint32(28, byteRate, Endian.little);
    final int blockAlign = _numChannels * (_bitsPerSample ~/ 8);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, _bitsPerSample, Endian.little);

    // data サブチャンク
    _writeAscii(header, 36, 'data');
    header.setUint32(40, dataLength, Endian.little);

    return header.buffer.asUint8List();
  }

  // ---------------------------------
  // -1.0〜1.0 の float を 16bit PCM（リトルエンディアン）に変換する
  // ---------------------------------
  static Uint8List _floatTo16BitPcm(List<double> samples) {
    final pcm = ByteData(samples.length * 2);
    for (int i = 0; i < samples.length; i++) {
      // 値域をはみ出したサンプルは飽和させる（クリッピング）
      final double clamped = samples[i].clamp(-1.0, 1.0);
      pcm.setInt16(i * 2, (clamped * 32767).round(), Endian.little);
    }
    return pcm.buffer.asUint8List();
  }

  // ---------------------------------
  // ASCII 文字列をヘッダの指定位置に書き込む
  // ---------------------------------
  static void _writeAscii(ByteData data, int offset, String value) {
    for (int i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }
}
