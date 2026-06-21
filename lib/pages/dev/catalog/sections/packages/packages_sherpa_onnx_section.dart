import 'package:flutter/material.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

// ============================================================
// sherpa_onnx パッケージの動作確認セクション
//   文字化エンジン本体を読み込めるか（ネイティブライブラリが起動するか）だけを確認する。
//   実際の音声認識・VAD はモデルファイルが必要なため、ここでは行わない。
//
//   initBindings() でネイティブの土台を初期化し、続けて getVersion() 等を呼ぶ。
//   バージョン文字列が返れば「ライブラリが読み込めて、実際に呼び出せた」ことの証明になる。
// ============================================================

class PackagesSherpaOnnxSection extends StatefulWidget {
  const PackagesSherpaOnnxSection({super.key});

  @override
  State<PackagesSherpaOnnxSection> createState() =>
      _PackagesSherpaOnnxSectionState();
}

class _PackagesSherpaOnnxSectionState extends State<PackagesSherpaOnnxSection> {
  bool _loaded = false;

  // 読み込み成功時に取得するエンジンの情報
  String? _version;
  String? _gitSha1;
  String? _gitDate;

  // 失敗時のエラーメッセージ
  String? _errorMessage;

  // ---------------------------------
  // エンジンの読み込み
  //   initBindings() でネイティブを初期化し、getVersion() で実際に呼び出せるか確かめる
  // ---------------------------------

  void _loadEngine() {
    try {
      // ネイティブライブラリの初期化（最初に1回だけ呼ぶ）
      sherpa.initBindings();

      // 初期化できただけでなく、実際にネイティブを呼べることまで確認する
      final version = sherpa.getVersion();
      final gitSha1 = sherpa.getGitSha1();
      final gitDate = sherpa.getGitDate();

      setState(() {
        _loaded = true;
        _version = version;
        _gitSha1 = gitSha1;
        _gitDate = gitDate;
        _errorMessage = null;
      });
    } catch (error) {
      setState(() {
        _loaded = false;
        _errorMessage = 'エンジンの読み込みに失敗しました: $error';
      });
    }
  }

  // ---------------------------------
  // ビルド
  // ---------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---------------------------------
        // 説明
        // ---------------------------------
        Text(
          'sherpa_onnx（文字化エンジン）が読み込めるかを確認します。\n'
          'モデルはまだ無いので、ここで確認できるのは「エンジンの読み込み」までです。',
          style: theme.textTheme.bodyMedium,
        ),
        const Divider(height: 32),

        // ---------------------------------
        // 読み込みボタン
        // ---------------------------------
        FilledButton(
          onPressed: _loaded ? null : _loadEngine,
          child: Text(_loaded ? '読み込み済み' : 'エンジンを読み込む'),
        ),
        const SizedBox(height: 12),

        // ---------------------------------
        // 結果表示
        // ---------------------------------
        if (_loaded) ...[
          Text(
            '✓ 読み込み成功',
            style: theme.textTheme.titleSmall?.copyWith(
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 8),
          _InfoRow(label: 'バージョン', value: _version ?? '-'),
          _InfoRow(label: 'Git SHA1', value: _gitSha1 ?? '-'),
          _InfoRow(label: 'Git 日付', value: _gitDate ?? '-'),
        ] else if (_errorMessage != null) ...[
          Text(
            _errorMessage!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ] else ...[
          Text(
            'まだ読み込んでいません',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

// ラベルと値を縦に並べる1項目（バージョン等の表示用）
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
