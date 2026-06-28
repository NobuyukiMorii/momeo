import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:momeo/platform/asset_pack_delivery.dart';
import 'package:momeo/stt/stt_model_provisioner.dart';

// ============================================================
// STT モデルの配置状態を確認するセクション
//   SttModelProvisioner().provision() を呼び、3ファイル（NeMo本体・tokens・silero）の
//   「住所（パス）・サイズ・壊れていないか」を一覧表示する。
//   ここは「ちゃんと置けて、住所から読める状態か」を目で確かめるための画面。
// ============================================================

class SttModelsSection extends StatefulWidget {
  const SttModelsSection({super.key});

  @override
  State<SttModelsSection> createState() => _SttModelsSectionState();
}

class _SttModelsSectionState extends State<SttModelsSection> {
  // 窓口は1つだけ持ち、モデル一覧と自動DL状態カードで同じものを共有する
  // （同じ AssetPackDelivery を使うため）。
  final SttModelProvisioner _provisioner = SttModelProvisioner();

  bool _loading = true; // 住所解決・サイズ計測の最中
  SttModels? _models; // 解決できた3ファイルの状態
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // 窓口に問い合わせて、3ファイルの配置状態を取得する
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final models = await _provisioner.provision();
      if (!mounted) return;
      setState(() {
        _models = models;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'モデルの配置状態を取得できませんでした: $error';
        _loading = false;
      });
    }
  }

  // ---------------------------------
  // ビルド
  // ---------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _errorMessage!,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      );
    }

    final models = _models!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '文字化に使う3つのモデルが、決まった住所に正しく置けているかを確認します。',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),

        // Android の自動DL（fast-follow）状態。iOS は同梱なので出さない。
        if (Platform.isAndroid) ...[
          _ModelDownloadCard(
            provisioner: _provisioner,
            onCompleted: _load, // DL完了でモデル一覧を取り直す
          ),
          const SizedBox(height: 12),
        ],

        // 全体の準備状況をひとめで
        _OverallStatus(allValid: models.allValid),
        const SizedBox(height: 8),

        // 再取得（配置し直したあとに押す）
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('再取得'),
          ),
        ),
        const Divider(height: 24),

        // 各ファイルの状態
        for (final file in models.all) ...[
          _ModelFileCard(file: file),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

// ---------------------------------
// Android の自動DL（fast-follow）状態カード
//   窓口（provisioner）が公開する準備状態を購読して表示する。
//   ・最初の1回は現在状態を取得（変化通知は動いたときしか来ないため）
//   ・以降は変化を購読（進捗・完了）
//   ・完了に切り替わったら親へ通知し、モデル一覧を取り直してもらう
// ---------------------------------

class _ModelDownloadCard extends StatefulWidget {
  const _ModelDownloadCard({required this.provisioner, required this.onCompleted});

  final SttModelProvisioner provisioner;
  final VoidCallback onCompleted; // DL完了時に呼ぶ（一覧の再取得）

  @override
  State<_ModelDownloadCard> createState() => _ModelDownloadCardState();
}

class _ModelDownloadCardState extends State<_ModelDownloadCard> {
  AssetPackState? _state; // null の間は「取得中」
  StreamSubscription<AssetPackState>? _subscription;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _subscription = widget.provisioner.watchModelDownload().listen(_onUpdate);
  }

  // 画面を開いた時点の状態（スナップショット）を1回取得する。
  Future<void> _loadInitial() async {
    final state = await widget.provisioner.modelDownloadState();
    if (!mounted) return;
    setState(() => _state = state);
  }

  // 状態が変わるたびに呼ばれる。完了へ切り替わった瞬間だけ親へ通知する。
  void _onUpdate(AssetPackState state) {
    if (!mounted) return;
    final justCompleted = _state?.phase != AssetPackPhase.completed &&
        state.phase == AssetPackPhase.completed;
    setState(() => _state = state);
    if (justCompleted) widget.onCompleted();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  // 取得開始・再試行
  Future<void> _retry() async {
    await widget.provisioner.requestModelDownload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _state;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 見出し＋現在フェーズのバッジ
          Row(
            children: [
              Expanded(
                child: Text(
                  'NeMo 自動DL（fast-follow）',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (state != null)
                Builder(builder: (context) {
                  final badge = _phaseBadge(state.phase, theme);
                  return _StatusBadge(label: badge.label, color: badge.color);
                }),
            ],
          ),
          const SizedBox(height: 8),

          if (state == null)
            Text('状態を取得中…', style: theme.textTheme.bodySmall)
          else
            ..._buildStatusBody(state, theme),
        ],
      ),
    );
  }

  // フェーズごとの本文（進捗・説明・再試行ボタン）
  List<Widget> _buildStatusBody(AssetPackState state, ThemeData theme) {
    return [
      // DL中は進捗バーとバイト数
      if (state.phase == AssetPackPhase.downloading) ...[
        LinearProgressIndicator(value: state.progress),
        const SizedBox(height: 4),
        Text(
          '${_formatBytes(state.bytesDownloaded)} / '
          '${_formatBytes(state.totalBytes)} バイト',
          style: theme.textTheme.bodySmall,
        ),
      ],

      if (state.phase == AssetPackPhase.completed)
        Text('モデルは端末に届いています。', style: theme.textTheme.bodySmall),

      if (state.phase == AssetPackPhase.notStarted)
        Text(
          'まだ届いていません（開発では手置きのモデルを使用）。',
          style: theme.textTheme.bodySmall,
        ),

      if (state.phase == AssetPackPhase.failed)
        Text(
          'ダウンロードに失敗しました（コード: ${state.errorCode}）。',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
        ),

      // 失敗・未到着のときは取得を促せるように
      if (state.phase == AssetPackPhase.failed ||
          state.phase == AssetPackPhase.notStarted) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('取得 / 再試行'),
          ),
        ),
      ],
    ];
  }
}

// フェーズを、バッジの表示ラベルと色に変換する。
({String label, Color color}) _phaseBadge(AssetPackPhase phase, ThemeData theme) {
  switch (phase) {
    case AssetPackPhase.completed:
      return (label: '完了', color: Colors.green);
    case AssetPackPhase.downloading:
      return (label: 'DL中', color: Colors.blue);
    case AssetPackPhase.failed:
      return (label: '失敗', color: theme.colorScheme.error);
    case AssetPackPhase.notStarted:
      return (label: '未到着', color: Colors.orange);
  }
}

// ---------------------------------
// 全体の準備状況（3つとも OK か）
// ---------------------------------

class _OverallStatus extends StatelessWidget {
  const _OverallStatus({required this.allValid});

  final bool allValid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = allValid ? Colors.green : theme.colorScheme.error;
    final label = allValid ? '3つとも準備OK' : '未準備のモデルがあります';

    return Row(
      children: [
        Icon(
          allValid ? Icons.check_circle : Icons.error,
          color: color,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

// ---------------------------------
// 1ファイルぶんのカード（住所・サイズ・整合性）
// ---------------------------------

class _ModelFileCard extends StatelessWidget {
  const _ModelFileCard({required this.file});

  final SttModelFile file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _statusOf(file, theme);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 見出し（ラベル ＋ 状態バッジ）
          Row(
            children: [
              Expanded(
                child: Text(
                  file.label,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              _StatusBadge(label: status.label, color: status.color),
            ],
          ),
          const SizedBox(height: 4),

          // ファイル名
          Text(
            file.fileName,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),

          // 住所（パス）
          _LabeledValue(
            label: '住所',
            value: file.path.isEmpty ? '（まだ無い）' : file.path,
          ),
          const SizedBox(height: 4),

          // サイズ（実際 / 期待）
          _LabeledValue(
            label: 'サイズ',
            value: '${_formatBytes(file.actualBytes)} / '
                '${_formatBytes(file.expectedBytes)} バイト'
                '${file.isValid ? '（一致）' : ''}',
          ),
        ],
      ),
    );
  }

  // 状態（OK / サイズ不一致 / 未配置）と色を決める
  _FileStatus _statusOf(SttModelFile file, ThemeData theme) {
    if (file.isValid) {
      return _FileStatus(label: 'OK', color: Colors.green);
    }
    if (file.exists) {
      return _FileStatus(label: 'サイズ不一致', color: Colors.orange);
    }
    return _FileStatus(label: '未配置', color: theme.colorScheme.error);
  }
}

// 状態のラベルと色をまとめただけの器
class _FileStatus {
  const _FileStatus({required this.label, required this.color});

  final String label;
  final Color color;
}

// 状態バッジ（OK / サイズ不一致 / 未配置）
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

// 「ラベル: 値」の1行（値は長くても折り返す）
class _LabeledValue extends StatelessWidget {
  const _LabeledValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(value, style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}

// ---------------------------------
// バイト数を読みやすくカンマ区切りにする（intl 等に依存しない自前ヘルパー）
//   例: 655542604 → "655,542,604"／-1（未配置）→ "─"
// ---------------------------------

String _formatBytes(int bytes) {
  if (bytes < 0) return '─';

  final digits = bytes.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    // 先頭以外で、残りの桁数が3の倍数になる位置にカンマを入れる
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
