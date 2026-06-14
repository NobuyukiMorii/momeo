import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vosk_flutter_service/vosk_flutter.dart';

// =====================================================================
// PackagesVoskJaSection — Vosk(日本語) ストリーミングの観察セクション
//
// B-2 の比較対象その2。sherpa-onnx が「発話終了→即確定（~50ms）」なのに対し、
// Vosk は **真のストリーミング**で「話している最中に文字が逐次出る」体験を見る。
//   ・Vosk 自身がマイクを掴み、PCM を内部で処理（VAD は使わない）
//   ・onPartial（暫定）= 喋りながら更新される途中経過
//   ・onResult（確定）= Vosk が無音で区切ったときに確定テキスト
//
// モデルは vosk_flutter_service の ModelLoader.loadFromNetwork で
// 自動ダウンロード＆解凍（vosk-model-small-ja-0.22, 約48MB・キャッシュあり）。
// sherpa のような adb 手動配置は不要。
//
// 関連文書: docs/research/continuous_listening/vad_whisper_impl_log.md（B-2）
// =====================================================================
class PackagesVoskJaSection extends StatefulWidget {
  const PackagesVoskJaSection({super.key});

  @override
  State<PackagesVoskJaSection> createState() => _PackagesVoskJaSectionState();
}

class _PackagesVoskJaSectionState extends State<PackagesVoskJaSection> {
  // 日本語の小モデル（約48MB）。初回に自動DL＆解凍してキャッシュする
  static const String _modelUrl =
      'https://alphacephei.com/vosk/models/vosk-model-small-ja-0.22.zip';
  static const int _sampleRate = 16000;

  // ---------------------------------
  // パッケージ本体
  // ---------------------------------
  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  StreamSubscription<String>? _partialSub;
  StreamSubscription<String>? _resultSub;

  // ---------------------------------
  // 状態
  // ---------------------------------
  bool _listening = false; // 認識中か
  bool _ready = false; // モデル＋サービスが用意できているか
  bool _busy = false; // 準備（DL含む）中か
  String _partialText = ''; // 暫定テキスト（喋りながら更新される）

  // ---------------------------------
  // 確定セグメント（新しいものを先頭に）
  // ---------------------------------
  final List<_Segment> _segments = [];
  int _segmentSeq = 0;

  // ---------------------------------
  // イベントログ
  // ---------------------------------
  final List<_LogEntry> _logs = [];

  @override
  void dispose() {
    _partialSub?.cancel();
    _resultSub?.cancel();
    _speechService?.stop();
    _speechService?.dispose();
    super.dispose();
  }

  // =====================================================================
  // モデル準備（自動DL）と認識サービスの用意
  // =====================================================================
  Future<void> _prepareService() async {
    if (_ready) return;
    setState(() => _busy = true);
    try {
      _log('model', 'モデルを準備（初回は約48MBのDL・解凍）');
      // ネットからDL＆解凍（キャッシュ済みなら即返る）。返り値は端末上のモデルパス
      final modelPath = await ModelLoader().loadFromNetwork(_modelUrl);
      _log('model', 'モデル展開先: $modelPath');

      _model = await _vosk.createModel(modelPath);
      _recognizer = await _vosk.createRecognizer(
        model: _model!,
        sampleRate: _sampleRate,
      );
      _speechService = await _vosk.initSpeechService(_recognizer!);

      // 逐次（暫定）と確定のストリームを購読する
      _partialSub = _speechService!.onPartial().listen(_onPartial);
      _resultSub = _speechService!.onResult().listen(_onResult);

      _log('model', '認識サービスを準備（sampleRate=$_sampleRate）');
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (error) {
      _log('error', 'モデル準備に失敗: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // =====================================================================
  // 認識の開始・停止
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

    await _prepareService();
    if (_speechService == null) return;

    _log('call', 'speechService.start');
    try {
      await _speechService!.start();
      setState(() {
        _listening = true;
        _partialText = '';
      });
    } catch (error) {
      _log('error', 'start で例外: $error');
    }
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    _log('call', 'speechService.stop');
    await _speechService?.stop();
    setState(() {
      _listening = false;
      _partialText = '';
    });
  }

  // 暫定結果（喋りながら来る）。JSON {"partial":"..."}
  void _onPartial(String json) {
    final text = _extractField(json, 'partial');
    setState(() => _partialText = text);
  }

  // 確定結果（無音区切りで来る）。JSON {"text":"..."}
  void _onResult(String json) {
    final text = _extractField(json, 'text');
    if (text.isEmpty) return;
    final segment = _Segment(id: ++_segmentSeq, text: text);
    setState(() {
      _segments.insert(0, segment);
      _partialText = '';
    });
    _log('asr', 'seg#${segment.id} 確定 "$text"');
  }

  // Vosk が返す JSON 文字列から指定キーの文字列を取り出す
  String _extractField(String json, String key) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return (map[key] as String? ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  // =====================================================================
  // ログ
  // =====================================================================
  void _log(String tag, String message) {
    debugPrint('[vosk-ja][$tag] $message');
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
          _buildPartialSection(),
          const SizedBox(height: 16),
          _buildSegmentsSection(),
          const SizedBox(height: 16),
          _buildLogSection(),
        ],
      ),
    );
  }

  Widget _buildMethodsSection() {
    return _Section(
      title: '1. メソッド（手動操作）',
      child: Column(
        children: [
          _methodRow(
            button: _MethodButton(
              label: _busy ? '準備中…' : 'モデル準備',
              onPressed: _busy ? null : _prepareService,
            ),
            desc: 'Vosk 日本語モデルを用意（初回は約48MBを自動DL＆解凍）。'
                'リスニング開始でも自動実行',
          ),
          _methodRow(
            button: _MethodButton(
              label: 'リスニング開始',
              color: const Color(0xFF16A34A),
              onPressed: _listening ? null : _startListening,
            ),
            desc: 'Vosk がマイクを掴み、話しながら逐次認識する',
          ),
          _methodRow(
            button: _MethodButton(
              label: 'リスニング停止',
              color: const Color(0xFFF59E0B),
              onPressed: _listening ? _stopListening : null,
            ),
            desc: '認識を止める',
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

  Widget _buildStatusSection() {
    return _Section(
      title: '2. 現在の状態',
      child: Column(
        children: [
          _StatRow(
            label: 'listening（認識中）',
            value: '$_listening',
            highlight: _listening,
          ),
          _StatRow(label: 'engine', value: 'Vosk small-ja-0.22'),
          _StatRow(
            label: 'ready（準備済み）',
            value: _busy ? '準備中…' : '$_ready',
            highlight: _ready,
          ),
        ],
      ),
    );
  }

  // 逐次（暫定）テキスト — このセクションの主役。喋りながら更新される
  Widget _buildPartialSection() {
    return _Section(
      title: '3. 逐次テキスト（暫定・話しながら更新）',
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Text(
          _partialText.isEmpty ? '(ここに話しながら文字が出ます)' : _partialText,
          style: TextStyle(
            fontSize: 18,
            color: _partialText.isEmpty
                ? const Color(0xFF9CA3AF)
                : const Color(0xFF065F46),
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentsSection() {
    return _Section(
      title: '4. 確定セグメント（${_segments.length}件）',
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
                '(まだ確定なし)',
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

  Widget _buildLogSection() {
    return _Section(
      title: '5. イベントログ（新しい順）',
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
              height: 240,
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
            '長押しで全ログをコピー',
            style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// 確定セグメント1件
// =====================================================================
class _Segment {
  const _Segment({required this.id, required this.text});

  final int id;
  final String text;
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'seg#${segment.id}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              segment.text,
              style: const TextStyle(fontSize: 15, color: Color(0xFF111827)),
            ),
          ),
        ],
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
