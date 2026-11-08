import 'dart:io';

import 'package:flutter/material.dart';
import 'package:momeo/diagnostics/device_log.dart';
import 'package:share_plus/share_plus.dart';

// ============================================================
// アプリ内に残したログ（DeviceLog のファイル）を読むセクション
//   日を選んで新しい順に並べ、先頭の [分類] で絞り込める。共有シートでファイルごと書き出せる。
// ============================================================

// 1行の先頭「時刻 [分類]」から分類を取り出す
final _tagPattern = RegExp(r'^\S+ \[([^\]]+)\]');

class DiagnosticsLogSection extends StatefulWidget {
  const DiagnosticsLogSection({super.key});

  @override
  State<DiagnosticsLogSection> createState() => _DiagnosticsLogSectionState();
}

class _DiagnosticsLogSectionState extends State<DiagnosticsLogSection> {
  List<File> _files = const [];
  File? _selectedFile;

  // 選んだ日の行（新しい順）
  List<String> _lines = const [];

  // 絞り込み中の分類（null はすべて）
  String? _selectedTag;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  // ---------------------------------
  // 読み込み
  // ---------------------------------
  // 日の一覧を読み直す。選んでいた日が残っていればそのまま、無ければ最新の日を開く
  Future<void> _reload() async {
    final files = await DeviceLog.logFiles();
    File? fileToOpen;
    for (final file in files) {
      if (file.path == _selectedFile?.path) fileToOpen = file;
    }
    fileToOpen ??= files.isEmpty ? null : files.first;
    if (!mounted) return;
    setState(() => _files = files);
    await _open(fileToOpen);
  }

  Future<void> _open(File? file) async {
    final lines = file == null ? <String>[] : await file.readAsLines();
    if (!mounted) return;
    setState(() {
      _selectedFile = file;
      _lines = lines.reversed.toList();
      _loading = false;
    });
  }

  // ---------------------------------
  // 書き出し
  // ---------------------------------
  Future<void> _share(BuildContext buttonContext) async {
    final file = _selectedFile;
    if (file == null) return;
    // iPad では共有シートを出す位置が必要
    final box = buttonContext.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/plain')],
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final theme = Theme.of(context);
    final tags = _tagsIn(_lines);
    final visibleLines = _selectedTag == null
        ? _lines
        : _lines.where((line) => _tagOf(line) == _selectedTag).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---------------------------------
        // 日の選択・読み直し・書き出し
        // ---------------------------------
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: _files.isEmpty
                    ? Text('まだログはありません', style: theme.textTheme.bodyMedium)
                    : DropdownButton<String>(
                        value: _selectedFile?.path,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final file in _files)
                            DropdownMenuItem(
                              value: file.path,
                              child: Text(_dayOf(file)),
                            ),
                        ],
                        onChanged: (path) {
                          final file = _files.firstWhere((f) => f.path == path);
                          setState(() => _selectedTag = null);
                          _open(file);
                        },
                      ),
              ),
              IconButton(
                tooltip: '読み直す',
                icon: const Icon(Icons.refresh),
                onPressed: _reload,
              ),
              Builder(
                builder: (buttonContext) => IconButton(
                  tooltip: '書き出す',
                  icon: const Icon(Icons.ios_share),
                  onPressed:
                      _selectedFile == null ? null : () => _share(buttonContext),
                ),
              ),
            ],
          ),
        ),
        // ---------------------------------
        // 分類での絞り込み
        // ---------------------------------
        if (tags.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _tagChip(label: 'すべて', tag: null),
                for (final tag in tags) _tagChip(label: tag, tag: tag),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            '${visibleLines.length} 件（新しい順）',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Divider(height: 1),
        // ---------------------------------
        // ログの行
        // ---------------------------------
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: visibleLines.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) => SelectableText(
              visibleLines[index],
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'Menlo',
                fontFamilyFallback: const ['monospace'],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tagChip({required String label, required String? tag}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _selectedTag == tag,
        onSelected: (_) => setState(() => _selectedTag = tag),
      ),
    );
  }

  // 行に出てくる分類（名前順）
  List<String> _tagsIn(List<String> lines) {
    final tags = <String>{};
    for (final line in lines) {
      final tag = _tagOf(line);
      if (tag != null) tags.add(tag);
    }
    return tags.toList()..sort();
  }

  String? _tagOf(String line) => _tagPattern.firstMatch(line)?.group(1);

  // ファイル名（yyyy-MM-dd.log）から日付を取り出す
  String _dayOf(File file) =>
      file.uri.pathSegments.last.replaceAll('.log', '');
}
