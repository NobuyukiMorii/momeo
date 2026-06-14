import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vad/vad.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

import 'package:momeo/utils/wav_writer.dart';
// 同梱の downloadModel は整合性検証が無く壊れたモデルを保存しうるため、
// 検証付きの自前ダウンローダを使う
import 'package:momeo/utils/whisper_model_downloader.dart';

// =====================================================================
// PackagesVadWhisperSection — VAD + Whisper パイプラインの観察セクション
//
// 実アプリの本番フローではなく、「連続録音 → 無音区切り → Whisper 転写」の
// 新方式を実機で見える化して触るためのもの。
//   ① vad パッケージがマイクを掴みっぱなしで連続キャプチャ
//   ② 発話の終わり（onSpeechEnd）で音声サンプルを切り出す
//   ③ サンプルを WAV にして whisper_flutter_new でバッチ転写
//   ④ 発話ごとに1件「セグメント」として転写結果を並べる
//
// speech_to_text セクションと同じく Catalog の Packages から開く。
// 本番 ListeningPage への結線は、この観察で精度・速度を確かめてから行う。
//
// 関連文書: docs/research/continuous_listening/recording_segmentation_whisper.md
// =====================================================================
class PackagesVadWhisperSection extends StatefulWidget {
  const PackagesVadWhisperSection({super.key});

  @override
  State<PackagesVadWhisperSection> createState() =>
      _PackagesVadWhisperSectionState();
}

class _PackagesVadWhisperSectionState extends State<PackagesVadWhisperSection> {
  // ---------------------------------
  // パッケージ本体
  // ---------------------------------
  VadHandler? _vad; // VAD（マイク所有者）
  Whisper? _whisper; // Whisper 転写エンジン（モデル変更時に作り直す）
  final List<StreamSubscription<dynamic>> _vadSubscriptions = [];

  // ---------------------------------
  // 転写の直列化
  // 発話が連続するとセグメントが重なるため、転写は1件ずつ順番に処理する
  // ---------------------------------
  Future<void> _transcribeChain = Future.value();

  // ---------------------------------
  // 状態（現在値）
  // ---------------------------------
  bool _listening = false; // VAD リスニング中か
  bool _speaking = false; // 今まさに発話中か（onSpeechStart〜onSpeechEnd）
  bool _modelReady = false; // Whisper モデルが端末に用意できているか
  bool _modelBusy = false; // モデルのダウンロード中か
  String? _modelDir; // モデルの保存ディレクトリ（初回に確定）

  // ---------------------------------
  // VAD のライブ計測（onFrameProcessed で更新し、ティッカーで描画する）
  // ---------------------------------
  int _frameCount = 0; // 処理済みフレーム数
  double _speechProbability = 0.0; // 直近フレームの発話確率
  Timer? _ticker; // ライブ表示を 100ms ごとに更新するタイマー

  // ---------------------------------
  // 発話セグメント（新しいものを先頭に並べる）
  // ---------------------------------
  final List<_Segment> _segments = [];
  int _segmentSeq = 0; // セグメント通し番号

  // ---------------------------------
  // オプション（UIから変更可能）
  // ---------------------------------
  // Whisper モデル変種（fp16 / 量子化）。速度・精度の比較用に切り替えられる
  _WhisperVariant _variant = _whisperVariants.first;
  // 転写スレッド数（Pixel 8a は高性能コアが少ないため 4 前後が目安）
  int _threads = 4;
  // encoder の枠（mel単位）。-1=自動（発話長に合わせる・実験）、0=既定1500(30秒)、それ以外は固定値。
  // 小さいほど encoder の計算が減って速いが、枠を超える長さの発話は末尾が切れる。
  // ※自動(発話長連動)は実測で逆効果だった（枠を小さくし過ぎると精度が落ち、
  //   whisper の temperature fallback が走って遅くなる）。既定は固定 512 に戻した。
  int _audioCtx = 512;
  // 転写する言語（ja=日本語 / auto=自動判定 / en=英語）
  String _language = 'ja';
  // VAD モデル（v4 / v5。v5 はパッケージが各種フレーム数を自動調整する）
  String _vadModel = 'v4';
  // 発話の開始/終了を判定する確率しきい値
  double _positiveThreshold = 0.5;
  double _negativeThreshold = 0.35;

  // HuggingFace（whisper.cpp 公式 ggml 配布）のホスト
  static const String _hfHost =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';

  // 現在準備済みのモデルファイルのパス（診断ログ用）
  String? _currentModelPath;

  // ---------------------------------
  // イベントログ（全イベントを時系列で追記）
  // ---------------------------------
  final List<_LogEntry> _logs = [];

  @override
  void dispose() {
    _ticker?.cancel();
    _disposeVad();
    super.dispose();
  }

  // =====================================================================
  // モデル準備（ダウンロード）
  // =====================================================================

  // ---------------------------------
  // モデルの保存ルートディレクトリを用意する（無ければ作成）
  // ---------------------------------
  Future<String> _ensureModelDir() async {
    if (_modelDir != null) return _modelDir!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/whisper_models');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _modelDir = dir.path;
    return dir.path;
  }

  // ---------------------------------
  // 変種ごとの保存ディレクトリを返す（無ければ作成）
  // 量子化ファイルが標準モデルと同名（ggml-small.bin）で衝突しないよう、
  // 変種ごとにサブディレクトリで分ける（subdir が空なら whisper_models 直下）
  // ---------------------------------
  Future<String> _variantDir(_WhisperVariant variant) async {
    final root = await _ensureModelDir();
    if (variant.subdir.isEmpty) return root;
    final dir = Directory('$root/${variant.subdir}');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir.path;
  }

  // ---------------------------------
  // 選択中のモデルを端末に用意する
  // 既にファイルがあれば再利用、無ければ Hugging Face からダウンロードする
  // （small などは数百MB級。初回はネットワークと時間が必要）
  // ---------------------------------
  Future<void> _prepareModel() async {
    setState(() => _modelBusy = true);
    try {
      final variant = _variant;
      final dir = await _variantDir(variant);
      // 量子化ファイルも baseModel 名（ggml-small.bin 等）で保存する。
      // こうすると Whisper(model: baseModel, modelDir:) からそのまま読める。
      final destPath = variant.baseModel.getPath(dir);

      if (WhisperModelDownloader.isValidFile(destPath, variant.minValidBytes)) {
        _log('model', '${variant.label} は準備済み（再利用）');
      } else {
        _log(
          'model',
          '${variant.label} をダウンロード開始（${variant.approxSize}・時間がかかります）',
        );
        // 進捗は 10% 刻みでログに出す（チャンクごとに出すと多すぎるため）
        int lastBucket = -1;
        await WhisperModelDownloader.ensureFile(
          url: Uri.parse('$_hfHost/${variant.remoteFileName}'),
          destinationPath: destPath,
          minValidBytes: variant.minValidBytes,
          onProgress: (received, total) {
            if (total == null || total == 0) return;
            final bucket = received * 10 ~/ total;
            if (bucket == lastBucket) return;
            lastBucket = bucket;
            _log(
              'model',
              'DL ${bucket * 10}%  '
                  '(${_formatBytes(received)} / ${_formatBytes(total)})',
            );
          },
        );
        _log('model', '${variant.label} のダウンロード完了');
      }

      // 診断: 用意できたモデルの実サイズを記録（途中で切れた DL を検知するため）
      final modelFile = File(destPath);
      final modelBytes = modelFile.existsSync() ? modelFile.lengthSync() : -1;
      _log(
        'debug',
        '${variant.label} 実サイズ=${_formatBytes(modelBytes)}  path=$destPath',
      );

      // 転写エンジンを（モデルと保存先を固定して）組み立てる
      _currentModelPath = destPath;
      _whisper = Whisper(model: variant.baseModel, modelDir: dir);
      if (!mounted) return;
      setState(() => _modelReady = true);
    } catch (error) {
      _log('error', 'モデル準備に失敗: $error');
    } finally {
      if (mounted) setState(() => _modelBusy = false);
    }
  }

  // =====================================================================
  // リスニング（VAD）の開始・停止
  // =====================================================================

  // ---------------------------------
  // マイク権限を確認・要求する（許可されれば true）
  // ---------------------------------
  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _log('warn', 'マイク権限が許可されていない（status=$status）');
    }
    return status.isGranted;
  }

  // ---------------------------------
  // VAD リスニング開始
  // マイクは VAD が掴みっぱなしにするため、再起動の空白は構造的に発生しない
  // ---------------------------------
  Future<void> _startListening() async {
    if (_listening) return;

    if (!await _ensureMicPermission()) return;

    // VadHandler を用意してイベントを購読する
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

  // ---------------------------------
  // VAD リスニング停止
  // ---------------------------------
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

  // ---------------------------------
  // VAD のイベントを購読する（多重購読を避けるため先に解除）
  // ---------------------------------
  void _subscribeVad() {
    _clearVadSubscriptions();
    final vad = _vad!;

    _vadSubscriptions.addAll([
      // 発話の開始（仮）
      vad.onSpeechStart.listen((_) {
        setState(() => _speaking = true);
        _log('speech', '発話開始');
      }),
      // 発話の開始（最小フレーム数を満たして確定）
      vad.onRealSpeechStart.listen((_) {
        _log('speech', '発話確定（realStart）');
      }),
      // 発話の終了 → 音声サンプルが届く（ここが転写のトリガー）
      vad.onSpeechEnd.listen(_onSpeechEnd),
      // 誤検知（最小フレーム数に満たず破棄）
      vad.onVADMisfire.listen((_) {
        setState(() => _speaking = false);
        _log('speech', '誤検知（misfire・破棄）');
      }),
      // フレーム処理（ライブ計測用。描画はティッカー側でまとめて行う）
      vad.onFrameProcessed.listen((frame) {
        _frameCount++;
        _speechProbability = frame.isSpeech;
      }),
      // エラー
      vad.onError.listen((message) {
        _log('error', 'VAD エラー: $message');
      }),
    ]);
  }

  // ---------------------------------
  // 発話終了 → セグメントを作って転写キューに積む
  // ---------------------------------
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

    // 転写は1件ずつ順番に（直列化）。重い処理が UI を止めないよう非同期で繋ぐ
    _transcribeChain =
        _transcribeChain.then((_) => _transcribeSegment(segment, samples));
  }

  // ---------------------------------
  // 1セグメントを WAV 化して Whisper で転写する
  // ---------------------------------
  Future<void> _transcribeSegment(
    _Segment segment,
    List<double> samples,
  ) async {
    // モデル未準備なら先にダウンロード（初回セグメントで自動的に用意される）
    if (!_modelReady) {
      await _prepareModel();
    }
    final whisper = _whisper;
    if (whisper == null) {
      _updateSegment(segment.id, status: _SegmentStatus.error, text: 'モデル未準備');
      return;
    }

    final startedAt = DateTime.now();
    // finally で消せるよう try の外で宣言する
    String? wavPath;
    try {
      // VAD の float サンプルを WAV ファイルに書き出す
      final tempDir = await getTemporaryDirectory();
      wavPath = '${tempDir.path}/vad_segment_${segment.id}.wav';
      await WavWriter.writeToFile(samples: samples, filePath: wavPath);

      // -----------------------------------------------------------------
      // 診断ログ（libwhisper.so の SIGSEGV 切り分け用）
      // ネイティブ転写は別 isolate で走り、落ちると Dart の catch に来ない。
      // そのため「転写に渡す直前の入力の実体」をここで記録しておく。
      // クラッシュ時はこのログが最後に残るので、
      //   ・model サイズが期待値より極端に小さい → モデルDLが途中で切れている
      //   ・wav サイズ/サンプル数が 0 や異常 → WAV 生成側の問題
      // と切り分けられる。
      // -----------------------------------------------------------------
      final wavBytes = await File(wavPath).length();
      final modelPath = _currentModelPath ?? '(未準備)';
      final modelExists =
          _currentModelPath != null && File(_currentModelPath!).existsSync();
      final modelBytes = modelExists ? File(_currentModelPath!).lengthSync() : -1;
      // この発話で実際に使う encoder 枠（自動モードなら発話長から算出）
      final effectiveAudioCtx = _resolveAudioCtx(samples.length);
      _log(
        'debug',
        'seg#${segment.id} 転写開始直前  '
            'wav=${_formatBytes(wavBytes)}(${samples.length} samples)  '
            'model=${_formatBytes(modelBytes)}  variant=${_variant.id}  '
            'lang=$_language  threads=$_threads  '
            'audioCtx=$effectiveAudioCtx(${_audioCtx == -1 ? "auto" : "manual"})\n'
            'modelPath=$modelPath',
      );

      // バッチ転写（タイムスタンプ無しの本文だけを受け取る）
      final response = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: wavPath,
          language: _language,
          isNoTimestamps: true,
          threads: _threads,
        ),
        // encoder の枠を縮めて高速化（フォークしたネイティブが解釈する）
        audioCtx: effectiveAudioCtx,
      );

      final text = response.text.trim();
      final elapsed = DateTime.now().difference(startedAt);
      _updateSegment(
        segment.id,
        status: _SegmentStatus.done,
        text: text.isEmpty ? '(空の結果)' : text,
        elapsed: elapsed,
      );
      _log(
        'whisper',
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
    } finally {
      // 転写が終わったら一時WAVを削除する（成功・失敗どちらでも）。
      // 生の音声を端末に残さない方針。サンプル自体はメモリ上で自動解放される。
      if (wavPath != null) {
        final wavFile = File(wavPath);
        if (wavFile.existsSync()) {
          try {
            wavFile.deleteSync();
          } catch (_) {
            // 削除失敗は致命的でないので無視（OS のキャッシュ整理でいずれ消える）
          }
        }
      }
    }
  }

  // ---------------------------------
  // 指定 id のセグメントを更新する
  // ---------------------------------
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
  // 後片付け・ティッカー
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

  // ---------------------------------
  // ライブ表示（フレーム数・発話確率）を 100ms ごとに描画更新する
  // フレーム自体は毎フレーム来るため、描画はここでまとめて行い負荷を抑える
  // ---------------------------------
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

  // =====================================================================
  // ログ
  // =====================================================================
  void _log(String tag, String message) {
    // flutter run のコンソール（logcat）にも出す。
    // ネイティブクラッシュ時は「最後に出たログ」を端末ログから追えるようにするため。
    debugPrint('[vad+whisper][$tag] $message');
    if (!mounted) return;
    setState(() {
      _logs.insert(0, _LogEntry(DateTime.now(), tag, message));
    });
  }

  void _clearLog() {
    setState(() => _logs.clear());
  }

  // ---------------------------------
  // この発話で使う encoder 枠（audio_ctx）を決める
  // 自動モード（_audioCtx == -1）は発話長から必要な枠だけ算出する。
  // mel 枠は 1単位 ≒ 0.02秒（= 50単位/秒）。短い発話ほど枠が小さくなり速くなる。
  // ---------------------------------
  int _resolveAudioCtx(int sampleCount) {
    // 手動指定（0=既定の1500、それ以外は固定値）はそのまま使う
    if (_audioCtx >= 0) return _audioCtx;

    final seconds = sampleCount / 16000.0;
    // 必要枠 ＝ 秒 × 50。末尾欠けを避けるため 15% の余白と端数(16)を足す
    final frames = (seconds * 50 * 1.15).ceil() + 16;
    // 下限64(≒1.3秒)・上限1500(=既定30秒)に収める
    return frames.clamp(64, 1500);
  }

  // バイト数を読みやすい単位（B/KB/MB）に整形する（診断ログ用）
  String _formatBytes(int bytes) {
    if (bytes < 0) return 'なし';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // =====================================================================
  // ビルド
  // =====================================================================
  @override
  Widget build(BuildContext context) {
    // Scaffold/AppBar は CatalogDetailPage 側が用意するため、ここは body のみ返す
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

  // ---------------------------------
  // 1. メソッド（手動操作）
  // ---------------------------------
  Widget _buildMethodsSection() {
    return _Section(
      title: '1. メソッド（手動操作）',
      child: Column(
        children: [
          _methodRow(
            button: _MethodButton(
              label: _modelBusy ? '準備中…' : 'モデル準備',
              onPressed: _modelBusy ? null : _prepareModel,
            ),
            desc: '選択中の Whisper モデルを端末に用意する（無ければDL）。'
                '初回セグメントでも自動実行される',
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

  // ---------------------------------
  // 2. 現在の状態
  // ---------------------------------
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
          _StatRow(
            label: 'model',
            value: _variant.label,
          ),
          _StatRow(
            label: 'threads',
            value: '$_threads',
          ),
          _StatRow(
            label: 'audio_ctx',
            value: _audioCtx == -1
                ? '自動'
                : (_audioCtx == 0 ? '既定(1500)' : '$_audioCtx'),
          ),
          _StatRow(
            label: 'modelReady（準備済み）',
            value: _modelBusy ? 'ダウンロード中…' : '$_modelReady',
            highlight: _modelReady,
          ),
        ],
      ),
    );
  }

  // ---------------------------------
  // 3. ライブ（VAD のフレーム計測）
  // ---------------------------------
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

  // ---------------------------------
  // 4. 発話セグメント（転写結果）
  // ---------------------------------
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

  // ---------------------------------
  // 5. オプション
  // ---------------------------------
  Widget _buildOptionsSection() {
    return _Section(
      title: '5. オプション',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Whisper モデル変種（変更すると再準備が必要）
          Row(
            children: [
              const Text('Whisper モデル: '),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _variant.id,
                  items: _whisperVariants
                      .map((variant) => DropdownMenuItem(
                            value: variant.id,
                            child: Text('${variant.label} ${variant.approxSize}'),
                          ))
                      .toList(),
                  onChanged: (id) {
                    if (id == null) return;
                    final selected =
                        _whisperVariants.firstWhere((v) => v.id == id);
                    setState(() {
                      _variant = selected;
                      // モデルが変わったので準備し直す
                      _modelReady = false;
                      _whisper = null;
                      _currentModelPath = null;
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
              _variant.note,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ),
          // 転写スレッド数（変更は次の発話の転写から反映）
          Row(
            children: [
              const Text('threads（転写スレッド数）: '),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _threads,
                items: const [2, 4, 6, 8]
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(),
                onChanged: (n) => setState(() => _threads = n ?? 4),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Pixel 8a は高性能コアが少ないため 4 前後が目安。次の発話の転写から反映',
              style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ),
          // audio_ctx（encoder の枠。小さいほど速いが長い発話は末尾が切れる）
          Row(
            children: [
              const Text('audio_ctx: '),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: _audioCtx,
                  items: const [
                    DropdownMenuItem(
                        value: 512, child: Text('512（約10秒・既定）')),
                    DropdownMenuItem(value: 768, child: Text('768（約15秒）')),
                    DropdownMenuItem(value: 384, child: Text('384（約7.7秒）')),
                    DropdownMenuItem(value: 256, child: Text('256（約5秒）')),
                    DropdownMenuItem(value: 0, child: Text('既定 1500（30秒）')),
                    DropdownMenuItem(value: -1, child: Text('自動（発話長連動・実験）')),
                  ],
                  onChanged: (value) => setState(() => _audioCtx = value ?? 512),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '固定値は小さいほど速いが、枠より長い発話は末尾が切れる。'
              '自動は実測で逆効果（枠を小さくし過ぎると精度低下＋fallbackで遅くなる）',
              style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ),
          // 言語
          Row(
            children: [
              const Text('言語: '),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _language,
                items: const [
                  DropdownMenuItem(value: 'ja', child: Text('ja（日本語）')),
                  DropdownMenuItem(value: 'auto', child: Text('auto（自動判定）')),
                  DropdownMenuItem(value: 'en', child: Text('en（英語）')),
                ],
                onChanged: (language) =>
                    setState(() => _language = language ?? 'ja'),
              ),
            ],
          ),
          // VAD モデル
          Row(
            children: [
              const Text('VAD モデル: '),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _vadModel,
                items: const [
                  DropdownMenuItem(value: 'v4', child: Text('v4')),
                  DropdownMenuItem(value: 'v5', child: Text('v5')),
                ],
                onChanged: (model) =>
                    setState(() => _vadModel = model ?? 'v4'),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'VAD モデル・しきい値の変更はリスニング再開後に反映される',
              style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ),
          // しきい値
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

  // ---------------------------------
  // 6. イベントログ
  // ---------------------------------
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
            '長押しで全ログをクリップボードにコピー',
            style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Whisper モデルの変種（fp16 / 量子化）
//
// whisper_flutter_new の WhisperModel enum は ggml-<name>.bin 固定パスのため、
// 量子化モデル（ggml-small-q5_1.bin 等）はそのままでは表せない。そこで
//   ・baseModel       … Whisper() に渡す土台モデル（パス組み立てに使う）
//   ・remoteFileName  … HuggingFace 上の実ファイル名
//   ・subdir          … whisper_models 配下の保存サブディレクトリ（''=直下）
// をまとめて1つの変種として持ち、
//   <whisper_models>/<subdir>/ggml-<baseModel>.bin
// に量子化ファイルを保存することで Whisper(model: baseModel, modelDir:) に渡せる。
//
// 速度・精度の比較が目的なので、軽い順（q5_1 → q8_0 → fp16 → base）に並べる。
// =====================================================================
class _WhisperVariant {
  const _WhisperVariant({
    required this.id,
    required this.label,
    required this.baseModel,
    required this.remoteFileName,
    required this.subdir,
    required this.minValidBytes,
    required this.approxSize,
    required this.note,
  });

  final String id; // 内部識別・UI value・ログ表示
  final String label; // UI 表示名
  final WhisperModel baseModel; // Whisper() に渡す土台モデル
  final String remoteFileName; // HuggingFace 上の実ファイル名
  final String subdir; // whisper_models 配下の保存サブディレクトリ（''=直下）
  final int minValidBytes; // 健全性チェックの下限（壊れDL検知用）
  final String approxSize; // 目安サイズ（UI 表示）
  final String note; // 補足（UI 表示）
}

// 1MB（バイト）
const int _oneMb = 1024 * 1024;

// 選択できるモデル変種（軽い順）
const List<_WhisperVariant> _whisperVariants = [
  _WhisperVariant(
    id: 'small-q5_1',
    label: 'small-q5_1（量子化・推奨）',
    baseModel: WhisperModel.small,
    remoteFileName: 'ggml-small-q5_1.bin',
    subdir: 'small-q5_1',
    minValidBytes: 150 * _oneMb, // 実サイズ 約181MB
    approxSize: '約181MB',
    note: '精度ほぼ small・軽量。速度比較の本命',
  ),
  _WhisperVariant(
    id: 'small-q8_0',
    label: 'small-q8_0（量子化）',
    baseModel: WhisperModel.small,
    remoteFileName: 'ggml-small-q8_0.bin',
    subdir: 'small-q8_0',
    minValidBytes: 200 * _oneMb, // 実サイズ 約252MB
    approxSize: '約252MB',
    note: '精度 small・q5_1 より少し重い',
  ),
  _WhisperVariant(
    id: 'small-fp16',
    label: 'small（fp16・基準）',
    baseModel: WhisperModel.small,
    remoteFileName: 'ggml-small.bin',
    subdir: '', // 既存の whisper_models/ggml-small.bin を再利用
    minValidBytes: 400 * _oneMb, // 実サイズ 約465MB
    approxSize: '約465MB',
    note: '精度◎だが重い。比較の基準',
  ),
  _WhisperVariant(
    id: 'base-q5_1',
    label: 'base-q5_1（軽量）',
    baseModel: WhisperModel.base,
    remoteFileName: 'ggml-base-q5_1.bin',
    subdir: 'base-q5_1',
    minValidBytes: 40 * _oneMb, // 実サイズ 約57MB
    approxSize: '約57MB',
    note: '速いが日本語精度は base 相当',
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
  final Duration? elapsed; // 転写にかかった時間

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

// セグメント1件の表示カード
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
          // ヘッダ行（番号・長さ・状態・所要時間）
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
          // 転写テキスト（処理中はプレースホルダ）
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

  // タグごとに色分けして時系列を読みやすくする
  Color get color {
    switch (tag) {
      case 'whisper':
        return const Color(0xFF34D399);
      case 'speech':
        return const Color(0xFF60A5FA);
      case 'model':
        return const Color(0xFFA78BFA);
      case 'debug':
        return const Color(0xFFFCD34D);
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
// 共通の見た目部品
// =====================================================================

// セクションのカード枠
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

// メソッド呼び出しボタン
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

// ラベル + 値の1行
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

// スライダー1行
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
