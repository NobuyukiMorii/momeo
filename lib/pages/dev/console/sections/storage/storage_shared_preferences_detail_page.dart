import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momeo/constants/preferences_keys.dart';

// ---------------------------------
// SharedPreferences の1キーの詳細ページ
// キー名・型・値の確認と削除ができる
// ---------------------------------
class StorageSharedPreferencesDetailPage extends StatefulWidget {
  const StorageSharedPreferencesDetailPage({super.key, required this.entry});

  final PreferenceEntry entry;

  @override
  State<StorageSharedPreferencesDetailPage> createState() =>
      _StorageSharedPreferencesDetailPageState();
}

class _StorageSharedPreferencesDetailPageState
    extends State<StorageSharedPreferencesDetailPage> {
  Object? _value;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _value = _getValue(prefs, widget.entry);
      _loaded = true;
    });
  }

  Object? _getValue(SharedPreferences prefs, PreferenceEntry entry) {
    return switch (entry.type) {
      PreferenceType.boolean => prefs.getBool(entry.key),
    };
  }

  Future<void> _delete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(widget.entry.key);
    if (!mounted) return;
    setState(() => _value = null);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.entry.key)),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ---------------------------------
                // キー名
                // ---------------------------------
                _DetailRow(
                  label: 'Key',
                  child: SelectableText(
                    widget.entry.key,
                    style: textTheme.bodyMedium,
                  ),
                ),
                const Divider(),
                // ---------------------------------
                // 型
                // ---------------------------------
                _DetailRow(
                  label: 'Type',
                  child: Text(
                    widget.entry.type.label,
                    style: textTheme.bodyMedium,
                  ),
                ),
                const Divider(),
                // ---------------------------------
                // 値
                // ---------------------------------
                _DetailRow(
                  label: 'Value',
                  child: _value == null
                      ? Text(
                          'null',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      : SelectableText(
                          _value.toString(),
                          style: textTheme.bodyMedium,
                        ),
                ),
                const SizedBox(height: 32),
                // ---------------------------------
                // 削除ボタン（値が null の時は disabled）
                // ---------------------------------
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: _value != null ? _delete : null,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 64,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

// ---------------------------------
// ラベル + コンテンツの行
// ---------------------------------
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}
