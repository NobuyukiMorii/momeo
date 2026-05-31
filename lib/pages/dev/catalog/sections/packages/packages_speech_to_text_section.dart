import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

// =====================================================================
// PackagesSpeechToTextSection — speech_to_text パッケージの観察セクション
//
// 実アプリの実装ではなく、パッケージの挙動を「見える化」して触るためのもの。
// メソッド（initialize/listen/stop/cancel）を手動で叩き、ステータス・
// 認識結果・isFinal・音量・無音経過・タイムアウト・全イベントログを
// リアルタイムで観察できる。
// Catalog の Packages カテゴリから CatalogDetailPage の body として表示される。
// =====================================================================
class PackagesSpeechToTextSection extends StatefulWidget {
  const PackagesSpeechToTextSection({super.key});

  @override
  State<PackagesSpeechToTextSection> createState() =>
      _PackagesSpeechToTextSectionState();
}

class _PackagesSpeechToTextSectionState
    extends State<PackagesSpeechToTextSection> {
  // パッケージ本体
  final SpeechToText _speech = SpeechToText();

  // ---------------------------------
  // 状態（現在値）
  // ---------------------------------
  bool _initialized = false; // initialize() の結果
  String _status = '-'; // onStatus の最新値（listening/notListening/done）
  SpeechRecognitionError? _lastError; // onError の最新値

  // ---------------------------------
  // 認識結果（現在値）
  // ---------------------------------
  String _recognizedWords = '';
  bool _isFinal = false; // finalResult（= isFinal）
  double _confidence = 0.0;
  List<SpeechRecognitionWords> _alternates = const [];

  // ---------------------------------
  // 音量レベル（onSoundLevelChange）
  // 端末によって値域が異なるため、観測した最小・最大で正規化してバー表示する
  // ---------------------------------
  double _soundLevel = 0.0;
  double _minSoundLevel = 0.0;
  double _maxSoundLevel = 0.0;

  // ---------------------------------
  // タイミング計測
  // ---------------------------------
  DateTime? _listenStartedAt; // listen 開始時刻
  DateTime? _lastResultAt; // 最後に onResult が更新された時刻
  Duration _sinceLastResult = Duration.zero; // 無音（更新停止）の経過時間
  Duration _sinceListenStart = Duration.zero; // listen 開始からの経過時間
  Timer? _ticker; // 上記2つを毎フレーム更新するタイマー

  // ---------------------------------
  // listen オプション（UIから変更可能）
  // ---------------------------------
  double _pauseForSec = 3.0;
  double _listenForSec = 30.0;
  bool _partialResults = true;
  ListenMode _listenMode = ListenMode.confirmation;

  // ---------------------------------
  // ロケール
  // ---------------------------------
  // systemLocale が取得できなかった時の安全な既定
  static const String _fallbackLocaleId = 'en-US';

  // listenMode ごとの説明文
  static const Map<ListenMode, String> _listenModeDescs = {
    ListenMode.deviceDefault: 'OS / デバイスのデフォルト設定を使う',
    ListenMode.dictation: '長文の口述入力向け。継続的に認識し続ける',
    ListenMode.search: '検索クエリ向け。短い発話を素早く確定する',
    ListenMode.confirmation: '短い返答向け。「はい」「いいえ」などの確認操作を想定',
  };

  List<LocaleName> _locales = const [];
  String? _systemLocaleId;
  String? _selectedLocaleId;

  // ---------------------------------
  // イベントログ（最重要：全イベントを時系列で追記）
  // ---------------------------------
  final List<_LogEntry> _logs = [];

  @override
  void dispose() {
    _ticker?.cancel();
    _speech.cancel();
    super.dispose();
  }

  // =====================================================================
  // メソッド呼び出し（手動操作）
  // =====================================================================

  // ---------------------------------
  // initialize() — セッション初期化（1回だけ呼べばよい）
  // ---------------------------------
  Future<void> _onInitialize() async {
    _log('call', 'initialize() を呼び出し');
    try {
      final available = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
        debugLogging: true,
      );
      setState(() => _initialized = available);
      _log('init', 'initialize 完了 → available=$available');

      // 利用可能なロケール一覧とシステムロケールを取得
      if (available) {
        await _loadLocales();
      }
    } catch (e) {
      _log('error', 'initialize で例外: $e');
    }
  }

  // ---------------------------------
  // listen() — 認識開始
  // ---------------------------------
  Future<void> _onListen() async {
    if (!_initialized) {
      _log('warn', 'まだ initialize されていない');
      return;
    }

    // 認識結果の表示をリセット
    setState(() {
      _recognizedWords = '';
      _isFinal = false;
      _confidence = 0.0;
      _alternates = const [];
    });

    final options = SpeechListenOptions(
      partialResults: _partialResults,
      listenMode: _listenMode,
      pauseFor: Duration(milliseconds: (_pauseForSec * 1000).round()),
      listenFor: Duration(milliseconds: (_listenForSec * 1000).round()),
      localeId: _selectedLocaleId,
    );

    _log(
      'call',
      'listen() 呼び出し  partial=$_partialResults '
          'pauseFor=${_pauseForSec}s listenFor=${_listenForSec}s '
          'mode=${_listenMode.name} locale=${_selectedLocaleId ?? "(system)"}',
    );

    try {
      await _speech.listen(
        onResult: _onResult,
        onSoundLevelChange: _onSoundLevel,
        listenOptions: options,
      );
      // 経過計測を開始
      _startTicker();
      setState(() {});
    } catch (e) {
      _log('error', 'listen で例外: $e');
    }
  }

  // ---------------------------------
  // stop() — 認識を止めて結果を確定させる
  // ---------------------------------
  Future<void> _onStop() async {
    _log('call', 'stop() を呼び出し');
    await _speech.stop();
    _stopTicker();
    setState(() {});
  }

  // ---------------------------------
  // cancel() — 結果を捨てて中断する
  // ---------------------------------
  Future<void> _onCancel() async {
    _log('call', 'cancel() を呼び出し');
    await _speech.cancel();
    _stopTicker();
    setState(() {});
  }

  // ---------------------------------
  // reset — 全状態をリセットして初期化前に戻す
  // ---------------------------------
  Future<void> _onReset() async {
    _ticker?.cancel();
    await _speech.cancel();
    setState(() {
      _initialized = false;
      _status = '-';
      _lastError = null;
      _recognizedWords = '';
      _isFinal = false;
      _confidence = 0.0;
      _alternates = const [];
      _soundLevel = 0.0;
      _minSoundLevel = 0.0;
      _maxSoundLevel = 0.0;
      _listenStartedAt = null;
      _lastResultAt = null;
      _sinceLastResult = Duration.zero;
      _sinceListenStart = Duration.zero;
      _ticker = null;
      _locales = const [];
      _systemLocaleId = null;
      _selectedLocaleId = null;
      _logs.clear();
    });
    _log('call', 'リセット完了 → initialize() から再開してください');
  }

  // ---------------------------------
  // ロケール一覧の取得 ＋ 既定ロケールの自動採用
  //
  // 実アプリでの推奨パターンを再現：
  // listen() に null を渡すと iOS は Locale.current に転落して英語化するため、
  // initialize 後は systemLocale()（= ユーザーの第一言語）を明示的な既定として
  // 自動選択しておく。これにより日本人なら ja-JP、英語話者なら en-US に適応する。
  // systemLocale が null の稀なケースは安全な既定 'en-US' にフォールバックする。
  // ---------------------------------
  Future<void> _loadLocales() async {
    final locales = await _speech.locales();
    final system = await _speech.systemLocale();

    // 既定ロケールを決定（systemLocale を最優先、無ければ en-US）
    final defaultLocaleId = system?.localeId ?? _fallbackLocaleId;

    setState(() {
      _locales = locales;
      _systemLocaleId = system?.localeId;
      // 自動既定を採用（null = system default 任せにはしない）
      _selectedLocaleId = defaultLocaleId;
    });
    _log('init', 'locales=${locales.length}件  system=${system?.localeId}');
    _log('init', '既定ロケールを自動採用 → localeId=$defaultLocaleId');
  }

  // =====================================================================
  // コールバック（パッケージ → こちら）
  // =====================================================================

  // ---------------------------------
  // onStatus — listening / notListening / done
  // ---------------------------------
  void _onStatus(String status) {
    setState(() => _status = status);
    _log('status', status);
    // パッケージ側が自律的に終了したときもタイマーを止める
    if (status == 'notListening' || status == 'done') {
      _stopTicker();
    }
  }

  // ---------------------------------
  // onError — 認識エラー（permanent=true は復帰にエラー解消が必要）
  // ---------------------------------
  void _onError(SpeechRecognitionError error) {
    setState(() => _lastError = error);
    _log('error', '${error.errorMsg}  permanent=${error.permanent}');
  }

  // ---------------------------------
  // onResult — 認識テキストの更新（部分結果・最終結果の両方が届く）
  // finalResult（isFinal）が true になった瞬間が「確定トリガー①」
  // ---------------------------------
  void _onResult(SpeechRecognitionResult result) {
    setState(() {
      _recognizedWords = result.recognizedWords;
      _isFinal = result.finalResult;
      _confidence = result.confidence;
      _alternates = result.alternates;
      // 無音計測のために最終更新時刻を更新
      _lastResultAt = DateTime.now();
      _sinceLastResult = Duration.zero;
    });

    final kind = result.finalResult ? 'FINAL' : 'partial';
    _log(
      'result',
      '[$kind] "${result.recognizedWords}"  '
          'conf=${result.confidence.toStringAsFixed(2)} '
          'alt=${result.alternates.length}',
    );
  }

  // ---------------------------------
  // onSoundLevelChange — 入力音量（iOS は dB、Android は端末依存）
  // ---------------------------------
  void _onSoundLevel(double level) {
    setState(() {
      _soundLevel = level;
      if (level < _minSoundLevel) _minSoundLevel = level;
      if (level > _maxSoundLevel) _maxSoundLevel = level;
    });
  }

  // =====================================================================
  // 経過計測タイマー
  // =====================================================================

  // ---------------------------------
  // listen 開始からの経過 / 最終更新からの無音経過を 100ms ごとに更新
  // ---------------------------------
  void _startTicker() {
    _ticker?.cancel();
    final now = DateTime.now();
    _listenStartedAt = now;
    _lastResultAt = now;
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final current = DateTime.now();
      setState(() {
        if (_listenStartedAt != null) {
          _sinceListenStart = current.difference(_listenStartedAt!);
        }
        if (_lastResultAt != null) {
          _sinceLastResult = current.difference(_lastResultAt!);
        }
      });
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
          _buildResultSection(),
          const SizedBox(height: 16),
          _buildSoundLevelSection(),
          const SizedBox(height: 16),
          _buildTimingSection(),
          const SizedBox(height: 16),
          _buildOptionsSection(),
          const SizedBox(height: 16),
          _buildLogSection(),
        ],
      ),
    );
  }

  // ---------------------------------
  // 1. メソッドボタン群
  // ---------------------------------
  Widget _buildMethodsSection() {
    return _Section(
      title: '1. メソッド（手動操作）',
      child: Column(
        children: [
          _methodRow(
            button: _MethodButton(
              label: 'initialize()',
              onPressed: _onInitialize,
            ),
            desc: '最初に1回だけ呼ぶ。エンジンの準備 + ロケール一覧の取得',
          ),
          _methodRow(
            button: _MethodButton(
              label: 'listen()',
              color: const Color(0xFF16A34A),
              onPressed: _initialized ? _onListen : null,
            ),
            desc: '音声認識を開始する。オプションはセクション6で設定',
          ),
          _methodRow(
            button: _MethodButton(
              label: 'stop()',
              color: const Color(0xFFF59E0B),
              onPressed: _initialized ? _onStop : null,
            ),
            desc: '認識を止め、それまでの結果を確定させる（isFinal = true が届く）',
          ),
          _methodRow(
            button: _MethodButton(
              label: 'cancel()',
              color: const Color(0xFFDC2626),
              onPressed: _initialized ? _onCancel : null,
            ),
            desc: '認識を即座に打ち切り、結果を破棄する',
          ),
          const Divider(height: 20),
          _methodRow(
            button: _MethodButton(
              label: 'reset',
              color: const Color(0xFF6B7280),
              onPressed: _onReset,
            ),
            desc: '全状態・タイミング・ログをリセットし、初期化前に戻す',
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
          button,
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
            label: 'initialized (isAvailable)',
            value: '$_initialized',
            highlight: _initialized,
          ),
          _StatRow(
            label: 'onStatus',
            value: _status,
            highlight: _status == SpeechToText.listeningStatus,
          ),
          _StatRow(label: 'isListening', value: '${_speech.isListening}'),
          _StatRow(
            label: 'lastError',
            value: _lastError == null
                ? '(none)'
                : '${_lastError!.errorMsg} (permanent=${_lastError!.permanent})',
            isError: _lastError != null,
          ),
        ],
      ),
    );
  }

  // ---------------------------------
  // 3. 認識結果
  // ---------------------------------
  Widget _buildResultSection() {
    return _Section(
      title: '3. 認識結果',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // isFinal を大きく目立たせる（確定トリガーの観察用）
          Row(
            children: [
              _Badge(
                text: _isFinal ? 'isFinal = TRUE' : 'isFinal = false',
                color: _isFinal
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 8),
              Text('confidence: ${_confidence.toStringAsFixed(3)}'),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Text(
              _recognizedWords.isEmpty ? '(まだ認識結果なし)' : _recognizedWords,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          if (_alternates.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('alternates（候補一覧）:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ..._alternates.map(
              (alt) => Text(
                '・"${alt.recognizedWords}"  '
                'conf=${alt.confidence.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------
  // 4. 音量レベルメーター
  // ---------------------------------
  Widget _buildSoundLevelSection() {
    // 観測した最小・最大の範囲で 0.0〜1.0 に正規化する
    final range = _maxSoundLevel - _minSoundLevel;
    final normalized =
        range > 0 ? ((_soundLevel - _minSoundLevel) / range).clamp(0.0, 1.0) : 0.0;

    return _Section(
      title: '4. 音量レベル（onSoundLevelChange）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'raw: ${_soundLevel.toStringAsFixed(2)}  '
            '(min ${_minSoundLevel.toStringAsFixed(1)} / '
            'max ${_maxSoundLevel.toStringAsFixed(1)})',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: normalized,
              minHeight: 16,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor:
                  const AlwaysStoppedAnimation(Color(0xFF16A34A)),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------
  // 5. タイミング計測（無音タイマー / listen経過）
  // ---------------------------------
  Widget _buildTimingSection() {
    final silenceSec = _sinceLastResult.inMilliseconds / 1000.0;
    // 仕様の「1.5秒無音」を超えたら赤く表示して気づけるようにする
    final overSpecSilence = silenceSec >= 1.5 && _speech.isListening;

    return _Section(
      title: '5. タイミング計測',
      child: Column(
        children: [
          _StatRow(
            label: 'listen 開始からの経過',
            value: '${(_sinceListenStart.inMilliseconds / 1000).toStringAsFixed(1)} s',
          ),
          _StatRow(
            label: '最終更新からの無音経過',
            value: '${silenceSec.toStringAsFixed(1)} s',
            isError: overSpecSilence,
            highlight: overSpecSilence,
          ),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '※ 仕様の確定条件「1.5秒無音」を超えると赤表示。\n'
              '※ OS 側の自動タイムアウトが何秒で発動するかはログで確認。',
              style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------
  // 6. listen オプション
  // ---------------------------------
  Widget _buildOptionsSection() {
    return _Section(
      title: '6. listen オプション',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // pauseFor
          _SliderRow(
            label: 'pauseFor（無音で自動停止するまで）',
            value: _pauseForSec,
            min: 1,
            max: 10,
            suffix: 's',
            onChanged: (v) => setState(() => _pauseForSec = v),
          ),
          // listenFor
          _SliderRow(
            label: 'listenFor（最大リスニング時間）',
            value: _listenForSec,
            min: 5,
            max: 60,
            suffix: 's',
            onChanged: (v) => setState(() => _listenForSec = v),
          ),
          // partialResults
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('partialResults（部分結果を逐次受け取る）'),
            value: _partialResults,
            onChanged: (v) => setState(() => _partialResults = v),
          ),
          // listenMode
          Row(
            children: [
              const Text('listenMode: '),
              const SizedBox(width: 8),
              DropdownButton<ListenMode>(
                value: _listenMode,
                items: ListenMode.values
                    .map((m) => DropdownMenuItem(value: m, child: Text(m.name)))
                    .toList(),
                onChanged: (m) =>
                    setState(() => _listenMode = m ?? ListenMode.confirmation),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _listenModeDescs[_listenMode] ?? '',
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ),
          // OSが報告する音声認識のデフォルトロケール（実際の値）
          _StatRow(
            label: 'systemLocale（OSが報告する既定）',
            value: _systemLocaleId ?? '(initialize 前)',
          ),
          _StatRow(
            label: '利用可能ロケール数',
            value: '${_locales.length}',
          ),
          // locale
          Row(
            children: [
              const Text('localeId: '),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String?>(
                  isExpanded: true,
                  // 選択値が一覧に無い（フォールバック等）場合は null 表示に丸める
                  value: _locales.any((l) => l.localeId == _selectedLocaleId)
                      ? _selectedLocaleId
                      : null,
                  items: [
                    // null 選択時も「実際の system 値」が見えるようにラベルへ埋め込む
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('(system default → ${_systemLocaleId ?? "?"})'),
                    ),
                    ..._locales.map(
                      (l) => DropdownMenuItem<String?>(
                        value: l.localeId,
                        child: Text('${l.name} (${l.localeId})'),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedLocaleId = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------
  // 7. イベントログ
  // ---------------------------------
  Widget _buildLogSection() {
    return _Section(
      title: '7. イベントログ（新しい順）',
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
                  .map((e) => '${e.formattedTime} [${e.tag}] ${e.message}')
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
      case 'result':
        return const Color(0xFF34D399);
      case 'status':
        return const Color(0xFF60A5FA);
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
    this.isError = false,
  });

  final String label;
  final String value;
  final bool highlight;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final valueColor = isError
        ? const Color(0xFFDC2626)
        : (highlight ? const Color(0xFF16A34A) : const Color(0xFF111827));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF6B7280))),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: valueColor,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// バッジ
class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
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
    this.suffix = '',
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label : ${value.toStringAsFixed(1)}$suffix',
            style: const TextStyle(fontSize: 12)),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) * 2).round(),
          label: '${value.toStringAsFixed(1)}$suffix',
          onChanged: onChanged,
        ),
      ],
    );
  }
}
