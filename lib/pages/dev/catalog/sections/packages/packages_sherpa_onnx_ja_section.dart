import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vad/vad.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

// =====================================================================
// PackagesSherpaOnnxJaSection — VAD + sherpa-onnx(日本語) の観察セクション
//
// B-2（ストリーミング/高速エンジン）検証の一つ。
//   ・マイクは VAD が掴みっぱなしで連続キャプチャ（vad+whisper と同じ）
//   ・発話終了（onSpeechEnd）で音声サンプルを切り出す
//   ・sherpa-onnx の「日本語特化 zipformer transducer（ReazonSpeech・offline）」で転写
//
// 狙いは「whisper バッチ（~4秒）」との速度比較。sherpa の ja モデルは
// RTF ~0.05（int8）と激速で、同じ VAD区切り→バッチ方式でも“話し終えてほぼ即”を狙える。
// ※これは frame 単位の逐次表示（true streaming）ではない。日本語の streaming
//   zipformer は未提供のため、ここでは「高速オフライン＋VAD」を見る。
//
// モデルは大きく（int8で約150MB）配布が tar.bz2 のみのため、当面は dev 用に
// adb push で端末へ配置する（下記 _modelDir 配下に4ファイル）。未配置ならその旨を表示。
//
// 関連文書: docs/research/continuous_listening/vad_whisper_impl_log.md（B-2）
// =====================================================================
class PackagesSherpaOnnxJaSection extends StatefulWidget {
  const PackagesSherpaOnnxJaSection({super.key});

  @override
  State<PackagesSherpaOnnxJaSection> createState() =>
      _PackagesSherpaOnnxJaSectionState();
}

class _PackagesSherpaOnnxJaSectionState
    extends State<PackagesSherpaOnnxJaSection> {
  // ---------------------------------
  // パッケージ本体
  // ---------------------------------
  VadHandler? _vad; // VAD（マイク所有者）
  sherpa.OfflineRecognizer? _recognizer; // sherpa-onnx 転写器
  final List<StreamSubscription<dynamic>> _vadSubscriptions = [];
  bool _bindingsInitialized = false; // initBindings は一度だけ

  // ---------------------------------
  // 転写の直列化（sherpa の decode は同期。順番に処理して計測を綺麗にする）
  // ---------------------------------
  Future<void> _decodeChain = Future.value();

  // ---------------------------------
  // 状態（現在値）
  // ---------------------------------
  bool _listening = false; // VAD リスニング中か
  bool _speaking = false; // 今まさに発話中か
  bool _recognizerReady = false; // 転写器が用意できているか
  bool _recognizerBusy = false; // 転写器の構築中か
  bool _modelMissing = false; // モデルファイルが端末に無い

  // ---------------------------------
  // VAD のライブ計測
  // ---------------------------------
  int _frameCount = 0;
  double _speechProbability = 0.0;
  Timer? _ticker;

  // ---------------------------------
  // 発話セグメント（新しいものを先頭に）
  // ---------------------------------
  final List<_Segment> _segments = [];
  int _segmentSeq = 0;

  // ---------------------------------
  // オプション
  // ---------------------------------
  int _threads = 2; // 転写スレッド数
  double _positiveThreshold = 0.5;
  double _negativeThreshold = 0.35;
  final String _vadModel = 'v4';

  // ---------------------------------
  // 使用するモデル（dev: adb push で各 subdir に配置する）
  // 既定は軽量・高速の k2 Zipformer。NeMo CTC(0.6B) は精度比較用
  // ---------------------------------
  _SherpaModel _model = _sherpaModels.first;

  // ---------------------------------
  // イベントログ
  // ---------------------------------
  final List<_LogEntry> _logs = [];

  @override
  void dispose() {
    _ticker?.cancel();
    _disposeVad();
    _recognizer?.free();
    _recognizer = null;
    super.dispose();
  }

  // =====================================================================
  // 転写器（sherpa-onnx）の準備
  // =====================================================================

  // 選択中モデルの保存ディレクトリを返す（無ければ作成）
  //
  // アプリ内部ストレージ（/data/user/0/<pkg>/files/sherpa_models/<subdir>/）。
  // dev では adb の `run-as` でここへモデルを配置する（外部領域は adb 作成ファイルに
  // アプリ uid がアクセスできず Permission denied になるため内部に置く）。
  Future<String> _modelDirFor(_SherpaModel model) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/${model.subdir}');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir.path;
  }

  // 必要ファイルが揃っているか
  bool _modelFilesExist(String dir, _SherpaModel model) {
    return model.files.every((name) => File('$dir/$name').existsSync());
  }

  // 転写器を構築する（モデルが無ければその旨を表示）
  Future<void> _prepareRecognizer() async {
    if (_recognizer != null) return;
    setState(() => _recognizerBusy = true);
    try {
      final model = _model;
      final dir = await _modelDirFor(model);

      if (!_modelFilesExist(dir, model)) {
        setState(() => _modelMissing = true);
        _log('error', '${model.label} のモデル未配置。adb push が必要（保存先: $dir）');
        return;
      }
      setState(() => _modelMissing = false);

      // ネイティブライブラリの初期化（プロセスで一度だけ）
      if (!_bindingsInitialized) {
        sherpa.initBindings();
        _bindingsInitialized = true;
      }

      // モデルの種別ごとに config を組み立てる
      final sherpa.OfflineModelConfig modelConfig;
      switch (model.kind) {
        case _SherpaKind.transducer:
          modelConfig = sherpa.OfflineModelConfig(
            transducer: sherpa.OfflineTransducerModelConfig(
              encoder: '$dir/encoder.int8.onnx',
              decoder: '$dir/decoder.onnx',
              joiner: '$dir/joiner.int8.onnx',
            ),
            tokens: '$dir/tokens.txt',
            numThreads: _threads,
            debug: false,
          );
        case _SherpaKind.nemoCtc:
          modelConfig = sherpa.OfflineModelConfig(
            nemoCtc: sherpa.OfflineNemoEncDecCtcModelConfig(
              model: '$dir/model.int8.onnx',
            ),
            tokens: '$dir/tokens.txt',
            numThreads: _threads,
            debug: false,
          );
      }

      // モデルのロードは重い（NeMo は約625MB）。同期だが dev なので busy 表示で許容
      _recognizer = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(model: modelConfig),
      );
      _log('model', '${model.label} 転写器を準備（threads=$_threads）');
      if (!mounted) return;
      setState(() => _recognizerReady = true);
    } catch (error) {
      _log('error', '転写器の準備に失敗: $error');
    } finally {
      if (mounted) setState(() => _recognizerBusy = false);
    }
  }

  // =====================================================================
  // リスニング（VAD）の開始・停止
  // =====================================================================

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _log('warn', 'マイク権限が許可されていない（status=$status）');
    }
    return status.isGranted;
  }

  Future<void> _startListening() async {
    if (_listening) return;
    if (!await _ensureMicPermission()) return;

    // 先に転写器を用意（モデル未配置ならここで分かる）
    await _prepareRecognizer();
    if (_recognizer == null) return;

    _vad ??= VadHandler.create(isDebug: true);
    _subscribeVad();

    _log(
      'call',
      'startListening  vadModel=$_vadModel '
          'pos=${_positiveThreshold.toStringAsFixed(2)} '
          'neg=${_negativeThreshold.toStringAsFixed(2)}',
    );

    try {
      await _vad!.startListening(
        model: _vadModel,
        positiveSpeechThreshold: _positiveThreshold,
        negativeSpeechThreshold: _negativeThreshold,
      );
      _startTicker();
      setState(() => _listening = true);
    } catch (error) {
      _log('error', 'startListening で例外: $error');
    }
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    _log('call', 'stopListening');
    await _vad?.stopListening();
    _stopTicker();
    setState(() {
      _listening = false;
      _speaking = false;
    });
  }

  void _subscribeVad() {
    _clearVadSubscriptions();
    final vad = _vad!;
    _vadSubscriptions.addAll([
      vad.onSpeechStart.listen((_) {
        setState(() => _speaking = true);
        _log('speech', '発話開始');
      }),
      vad.onRealSpeechStart.listen((_) {
        _log('speech', '発話確定（realStart）');
      }),
      vad.onSpeechEnd.listen(_onSpeechEnd),
      vad.onVADMisfire.listen((_) {
        setState(() => _speaking = false);
        _log('speech', '誤検知（misfire・破棄）');
      }),
      vad.onFrameProcessed.listen((frame) {
        _frameCount++;
        _speechProbability = frame.isSpeech;
      }),
      vad.onError.listen((message) {
        _log('error', 'VAD エラー: $message');
      }),
    ]);
  }

  // 発話終了 → セグメントを作って転写キューに積む
  void _onSpeechEnd(List<double> samples) {
    final durationSec = samples.length / 16000.0;
    final segment = _Segment(
      id: ++_segmentSeq,
      sampleCount: samples.length,
      durationSec: durationSec,
    );
    setState(() {
      _speaking = false;
      _segments.insert(0, segment);
    });
    _log(
      'speech',
      '発話終了  seg#${segment.id}  '
          '${samples.length} samples (${durationSec.toStringAsFixed(1)}s)',
    );
    // 直列化（sherpa decode は同期なので順番に）
    _decodeChain =
        _decodeChain.then((_) async => _decodeSegment(segment, samples));
  }

  // 1セグメントを sherpa-onnx で転写する
  Future<void> _decodeSegment(_Segment segment, List<double> samples) async {
    final recognizer = _recognizer;
    if (recognizer == null) {
      _updateSegment(segment.id, status: _SegmentStatus.error, text: 'モデル未準備');
      return;
    }
    final startedAt = DateTime.now();
    try {
      // VAD の float サンプルをそのまま渡す（16kHz mono、値域 -1..1）
      final stream = recognizer.createStream();
      stream.acceptWaveform(
        samples: Float32List.fromList(samples),
        sampleRate: 16000,
      );
      recognizer.decode(stream);
      final text = recognizer.getResult(stream).text;
      stream.free();

      final elapsed = DateTime.now().difference(startedAt);
      _updateSegment(
        segment.id,
        status: _SegmentStatus.done,
        text: text.isEmpty ? '(空の結果)' : text,
        elapsed: elapsed,
      );
      _log(
        'asr',
        'seg#${segment.id} 転写完了 ${elapsed.inMilliseconds}ms "$text"',
      );
    } catch (error) {
      _updateSegment(
        segment.id,
        status: _SegmentStatus.error,
        text: 'エラー: $error',
        elapsed: DateTime.now().difference(startedAt),
      );
      _log('error', 'seg#${segment.id} 転写失敗: $error');
    }
  }

  void _updateSegment(
    int id, {
    required _SegmentStatus status,
    required String text,
    Duration? elapsed,
  }) {
    final index = _segments.indexWhere((segment) => segment.id == id);
    if (index < 0 || !mounted) return;
    setState(() {
      _segments[index] = _segments[index].copyWith(
        status: status,
        text: text,
        elapsed: elapsed,
      );
    });
  }

  // =====================================================================
  // 後片付け・ティッカー・ログ
  // =====================================================================

  void _clearVadSubscriptions() {
    for (final subscription in _vadSubscriptions) {
      subscription.cancel();
    }
    _vadSubscriptions.clear();
  }

  void _disposeVad() {
    _clearVadSubscriptions();
    _vad?.dispose();
    _vad = null;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _log(String tag, String message) {
    debugPrint('[sherpa-ja][$tag] $message');
    if (!mounted) return;
    setState(() {
      _logs.insert(0, _LogEntry(DateTime.now(), tag, message));
    });
  }

  void _clearLog() {
    setState(() => _logs.clear());
  }

  // =====================================================================
  // ビルド
  // =====================================================================
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF3F4F6),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMethodsSection(),
          const SizedBox(height: 16),
          _buildStatusSection(),
          const SizedBox(height: 16),
          _buildLiveSection(),
          const SizedBox(height: 16),
          _buildSegmentsSection(),
          const SizedBox(height: 16),
          _buildOptionsSection(),
          const SizedBox(height: 16),
          _buildLogSection(),
        ],
      ),
    );
  }

  // 1. メソッド
  Widget _buildMethodsSection() {
    return _Section(
      title: '1. メソッド（手動操作）',
      child: Column(
        children: [
          _methodRow(
            button: _MethodButton(
              label: _recognizerBusy ? '準備中…' : '転写器を準備',
              onPressed: _recognizerBusy ? null : _prepareRecognizer,
            ),
            desc: 'sherpa-onnx 転写器を構築（モデルが端末に必要）。'
                'リスニング開始でも自動実行',
          ),
          _methodRow(
            button: _MethodButton(
              label: 'リスニング開始',
              color: const Color(0xFF16A34A),
              onPressed: _listening ? null : _startListening,
            ),
            desc: 'マイクを掴み、VAD が発話を検出し始める',
          ),
          _methodRow(
            button: _MethodButton(
              label: 'リスニング停止',
              color: const Color(0xFFF59E0B),
              onPressed: _listening ? _stopListening : null,
            ),
            desc: 'マイクを離してリスニングを止める',
          ),
        ],
      ),
    );
  }

  Widget _methodRow({required Widget button, required String desc}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 120, child: button),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              desc,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ),
        ],
      ),
    );
  }

  // 2. 状態
  Widget _buildStatusSection() {
    return _Section(
      title: '2. 現在の状態',
      child: Column(
        children: [
          _StatRow(
            label: 'listening（リスニング中）',
            value: '$_listening',
            highlight: _listening,
          ),
          _StatRow(
            label: 'speaking（発話中）',
            value: '$_speaking',
            highlight: _speaking,
          ),
          _StatRow(label: 'model', value: _model.label),
          _StatRow(label: 'threads', value: '$_threads'),
          _StatRow(
            label: 'recognizerReady',
            value: _recognizerBusy
                ? '準備中…'
                : (_modelMissing ? 'モデル未配置' : '$_recognizerReady'),
            highlight: _recognizerReady,
          ),
        ],
      ),
    );
  }

  // 3. ライブ
  Widget _buildLiveSection() {
    final probability = _speechProbability.clamp(0.0, 1.0);
    return _Section(
      title: '3. ライブ（VAD）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatRow(label: '処理フレーム数', value: '$_frameCount'),
          const SizedBox(height: 8),
          Text(
            '発話確率: ${probability.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: probability,
              minHeight: 16,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: AlwaysStoppedAnimation(
                _speaking ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 4. セグメント
  Widget _buildSegmentsSection() {
    return _Section(
      title: '4. 発話セグメント（${_segments.length}件）',
      trailing: _segments.isEmpty
          ? null
          : TextButton(
              onPressed: () => setState(_segments.clear),
              child: const Text('クリア'),
            ),
      child: _segments.isEmpty
          ? const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '(まだ発話なし)',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            )
          : Column(
              children: _segments
                  .map((segment) => _SegmentTile(segment: segment))
                  .toList(),
            ),
    );
  }

  // 5. オプション
  Widget _buildOptionsSection() {
    return _Section(
      title: '5. オプション',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // モデル選択（変更すると転写器を作り直す）
          Row(
            children: [
              const Text('モデル: '),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _model.id,
                  items: _sherpaModels
                      .map((m) => DropdownMenuItem(
                            value: m.id,
                            child: Text(m.label),
                          ))
                      .toList(),
                  onChanged: (id) {
                    if (id == null) return;
                    final selected =
                        _sherpaModels.firstWhere((m) => m.id == id);
                    setState(() {
                      _model = selected;
                      _recognizer?.free();
                      _recognizer = null;
                      _recognizerReady = false;
                      _modelMissing = false;
                    });
                    _log('model', 'モデル変更 → ${selected.label}（再準備が必要）');
                  },
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _model.note,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ),
          Row(
            children: [
              const Text('threads（転写スレッド数）: '),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _threads,
                items: const [1, 2, 4]
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(),
                // スレッド変更は転写器の作り直しが必要
                onChanged: (n) {
                  if (n == null) return;
                  setState(() {
                    _threads = n;
                    _recognizer?.free();
                    _recognizer = null;
                    _recognizerReady = false;
                  });
                  _log('model', 'threads 変更 → $n（転写器を作り直す）');
                },
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'スレッド変更は次回の転写器準備から反映',
              style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ),
          _SliderRow(
            label: 'positiveSpeechThreshold（発話開始の判定）',
            value: _positiveThreshold,
            min: 0.1,
            max: 0.9,
            onChanged: (value) => setState(() => _positiveThreshold = value),
          ),
          _SliderRow(
            label: 'negativeSpeechThreshold（発話終了の判定）',
            value: _negativeThreshold,
            min: 0.1,
            max: 0.9,
            onChanged: (value) => setState(() => _negativeThreshold = value),
          ),
        ],
      ),
    );
  }

  // 6. ログ
  Widget _buildLogSection() {
    return _Section(
      title: '6. イベントログ（新しい順）',
      trailing: TextButton(
        onPressed: _clearLog,
        child: const Text('クリア'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () {
              if (_logs.isEmpty) return;
              final text = _logs
                  .map((entry) =>
                      '${entry.formattedTime} [${entry.tag}] ${entry.message}')
                  .join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ログをコピーしました')),
              );
            },
            child: Container(
              height: 280,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _logs.isEmpty
                  ? const Center(
                      child: Text('(ログなし)',
                          style: TextStyle(color: Color(0xFF6B7280))),
                    )
                  : ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final entry = _logs[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '${entry.formattedTime}  [${entry.tag}] ${entry.message}',
                            style: TextStyle(
                              color: entry.color,
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '長押しで全ログをコピー。モデル未配置のときは adb push が必要',
            style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// sherpa-onnx のモデル定義（種別ごとに config の組み立てが違う）
//
// 同じ ReazonSpeech データから作られた2系統を比較できるようにする：
//   ・k2 Zipformer transducer（159M）… encoder/decoder/joiner の3ファイル
//   ・NeMo parakeet CTC（0.6B）       … model.int8.onnx の単一ファイル
// dev では各 subdir（sherpa_models/...）へ adb の run-as で配置する。
// =====================================================================
enum _SherpaKind { transducer, nemoCtc }

class _SherpaModel {
  const _SherpaModel({
    required this.id,
    required this.label,
    required this.kind,
    required this.subdir,
    required this.files,
    required this.note,
  });

  final String id; // 内部識別・UI value
  final String label; // UI 表示名
  final _SherpaKind kind; // config の種別
  final String subdir; // sherpa_models 配下の保存サブディレクトリ
  final List<String> files; // 必要ファイル名（存在チェック用）
  final String note; // 補足（UI 表示）
}

const List<_SherpaModel> _sherpaModels = [
  _SherpaModel(
    id: 'zipformer',
    label: 'k2 Zipformer (159M)',
    kind: _SherpaKind.transducer,
    subdir: 'sherpa_models/ja-reazonspeech',
    files: ['encoder.int8.onnx', 'decoder.onnx', 'joiner.int8.onnx', 'tokens.txt'],
    note: 'ReazonSpeech k2系・軽量(約160MB)・高速（既定）',
  ),
  _SherpaModel(
    id: 'nemo-ctc',
    label: 'NeMo parakeet CTC (0.6B)',
    kind: _SherpaKind.nemoCtc,
    subdir: 'sherpa_models/ja-parakeet-ctc',
    files: ['model.int8.onnx', 'tokens.txt'],
    note: 'ReazonSpeech NeMo系・大型(約625MB)・高精度狙い（句読点も期待）',
  ),
];

// =====================================================================
// 発話セグメント1件
// =====================================================================
enum _SegmentStatus { transcribing, done, error }

class _Segment {
  const _Segment({
    required this.id,
    required this.sampleCount,
    required this.durationSec,
    this.status = _SegmentStatus.transcribing,
    this.text = '',
    this.elapsed,
  });

  final int id;
  final int sampleCount;
  final double durationSec;
  final _SegmentStatus status;
  final String text;
  final Duration? elapsed;

  _Segment copyWith({
    _SegmentStatus? status,
    String? text,
    Duration? elapsed,
  }) {
    return _Segment(
      id: id,
      sampleCount: sampleCount,
      durationSec: durationSec,
      status: status ?? this.status,
      text: text ?? this.text,
      elapsed: elapsed ?? this.elapsed,
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({required this.segment});

  final _Segment segment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'seg#${segment.id}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${segment.durationSec.toStringAsFixed(1)}s',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              const Spacer(),
              if (segment.elapsed != null)
                Text(
                  '${segment.elapsed!.inMilliseconds}ms',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
              const SizedBox(width: 8),
              _StatusBadge(status: segment.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            segment.status == _SegmentStatus.transcribing
                ? '転写中…'
                : segment.text,
            style: TextStyle(
              fontSize: 15,
              color: segment.status == _SegmentStatus.error
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final _SegmentStatus status;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (status) {
      _SegmentStatus.transcribing => ('転写中', const Color(0xFFF59E0B)),
      _SegmentStatus.done => ('完了', const Color(0xFF16A34A)),
      _SegmentStatus.error => ('エラー', const Color(0xFFDC2626)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}

// =====================================================================
// ログ1件
// =====================================================================
class _LogEntry {
  _LogEntry(this.time, this.tag, this.message);

  final DateTime time;
  final String tag;
  final String message;

  String get formattedTime {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    final ms = time.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  Color get color {
    switch (tag) {
      case 'asr':
        return const Color(0xFF34D399);
      case 'speech':
        return const Color(0xFF60A5FA);
      case 'model':
        return const Color(0xFFA78BFA);
      case 'error':
      case 'warn':
        return const Color(0xFFF87171);
      case 'call':
        return const Color(0xFFFBBF24);
      default:
        return const Color(0xFFD1D5DB);
    }
  }
}

// =====================================================================
// 共通の見た目部品（このセクション内専用）
// =====================================================================
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({
    required this.label,
    required this.onPressed,
    this.color = const Color(0xFF2563EB),
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFD1D5DB),
      ),
      child: Text(label),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: highlight
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF111827),
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label : ${value.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 12)),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) * 20).round(),
          label: value.toStringAsFixed(2),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
