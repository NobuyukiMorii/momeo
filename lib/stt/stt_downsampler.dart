import 'dart:math' show cos, pi, sin;
import 'dart:typed_data';

// ============================================================
// 48kHz の PCM16 を、認識の前提である 16kHz の PCM16 へ落とす係
//
//   iOS では録音に指定したサンプリングレートが端末全体の音の出入りに効き、
//   16kHz で録ると他のアプリの再生音まで 16kHz に落ちてこもる。
//   そのため iOS は 48kHz で録り、ここで 16kHz へ落としてから音声 isolate へ渡す。
//
//   やっていること：8kHz より上を削る（削らずに間引くと高い音が低い雑音に化ける）
//   → 3サンプルに1つだけ残す。チャンクの境目で途切れないよう、直前の音を持ち越す。
// ============================================================

const int _kInputSampleRate = 48000; // 受け取る音のサンプリングレート
const int _kOutputSampleRate = 16000; // 渡す音のサンプリングレート（VAD・認識モデルの前提）
const int _kDecimationFactor = _kInputSampleRate ~/ _kOutputSampleRate; // 何サンプルに1つ残すか

// 高い音を削るフィルタの設定。7kHz 付近から削り始め、8kHz を越える音はほぼ消える
const double _kCutoffHz = 7000;
const int _kFilterTaps = 63; // フィルタの長さ（長いほど鋭く削れるが計算が増える）

const int _kBytesPerSample = 2; // PCM16 = 1サンプル2バイト
const int _kInt16Amplitude = 32768; // PCM16 の正規化基準（2^15）

class SttDownsampler {
  SttDownsampler() : _coefficients = _buildLowPassCoefficients();

  // 録音に指定するサンプリングレート
  static const int inputSampleRate = _kInputSampleRate;

  final Float64List _coefficients;

  // 前のチャンクの末尾。次のチャンクの先頭の計算に使う
  Float64List _history = Float64List(_kFilterTaps - 1);

  // 次に残すサンプルの位置（今回のチャンクの先頭から何サンプル目か）
  int _nextOutputOffset = 0;

  // ---------------------------------
  // 録音の切れ目で持ち越しを捨てる
  // ---------------------------------
  void reset() {
    _history = Float64List(_kFilterTaps - 1);
    _nextOutputOffset = 0;
  }

  // ---------------------------------
  // 48kHz のチャンクを 16kHz のチャンクに変換する
  // ---------------------------------
  Uint8List convert(Uint8List pcm16Bytes) {
    // 持ち越した末尾と今回の音を1本につなぐ
    final inputSampleCount = pcm16Bytes.length ~/ _kBytesPerSample;
    final inputView = ByteData.sublistView(pcm16Bytes);
    final joined = Float64List(_history.length + inputSampleCount);
    joined.setAll(0, _history);
    for (var index = 0; index < inputSampleCount; index++) {
      joined[_history.length + index] =
          inputView.getInt16(index * _kBytesPerSample, Endian.little).toDouble();
    }

    // 3サンプルおきに、高い音を削った値を1つ作る
    final outputSamples = <int>[];
    var position = _history.length + _nextOutputOffset;
    while (position < joined.length) {
      outputSamples.add(_filteredSampleAt(joined, position));
      position += _kDecimationFactor;
    }

    // 次のチャンクへ持ち越す
    _nextOutputOffset = position - joined.length;
    _history = Float64List.sublistView(joined, joined.length - _history.length);

    // PCM16 little-endian のバイト列に戻す
    final outputBytes = Uint8List(outputSamples.length * _kBytesPerSample);
    final outputView = ByteData.sublistView(outputBytes);
    for (var index = 0; index < outputSamples.length; index++) {
      outputView.setInt16(index * _kBytesPerSample, outputSamples[index], Endian.little);
    }
    return outputBytes;
  }

  // position の位置で、直前 _kFilterTaps サンプルぶんを重み付きで足し合わせる
  int _filteredSampleAt(Float64List samples, int position) {
    var sum = 0.0;
    for (var tap = 0; tap < _kFilterTaps; tap++) {
      sum += _coefficients[tap] * samples[position - tap];
    }
    // PCM16 に収まらない値は端に寄せる
    return sum.round().clamp(-_kInt16Amplitude, _kInt16Amplitude - 1);
  }

  // ---------------------------------
  // 高い音を削るフィルタの重み（窓関数法のローパス、Hamming 窓）
  // ---------------------------------
  static Float64List _buildLowPassCoefficients() {
    final coefficients = Float64List(_kFilterTaps);
    final normalizedCutoff = _kCutoffHz / _kInputSampleRate;
    final center = (_kFilterTaps - 1) / 2;

    for (var tap = 0; tap < _kFilterTaps; tap++) {
      final distance = tap - center;
      final sinc = distance == 0
          ? 2 * normalizedCutoff
          : sin(2 * pi * normalizedCutoff * distance) / (pi * distance);
      final hammingWindow = 0.54 - 0.46 * cos(2 * pi * tap / (_kFilterTaps - 1));
      coefficients[tap] = sinc * hammingWindow;
    }

    // 音量が変わらないよう、重みの合計を1にそろえる
    final total = coefficients.reduce((sum, weight) => sum + weight);
    for (var tap = 0; tap < _kFilterTaps; tap++) {
      coefficients[tap] /= total;
    }
    return coefficients;
  }
}
