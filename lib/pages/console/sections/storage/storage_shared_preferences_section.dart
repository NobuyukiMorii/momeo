import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momeo/constants/preferences_keys.dart';
import 'package:momeo/pages/console/sections/storage/storage_shared_preferences_detail_page.dart';

class StorageSharedPreferencesSection extends StatefulWidget {
  const StorageSharedPreferencesSection({super.key});

  @override
  State<StorageSharedPreferencesSection> createState() =>
      _StorageSharedPreferencesSectionState();
}

class _StorageSharedPreferencesSectionState
    extends State<StorageSharedPreferencesSection> {
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _prefs = prefs);
  }

  Object? _getValue(PreferenceEntry entry) {
    return switch (entry.type) {
      PreferenceType.boolean => _prefs!.getBool(entry.key),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_prefs == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.separated(
      itemCount: PreferencesKeys.all.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = PreferencesKeys.all[index];
        final value = _getValue(entry);

        return _PreferenceTile(
          entry: entry,
          value: value,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StorageSharedPreferencesDetailPage(
                  entry: entry,
                ),
              ),
            );
            _load();
          },
        );
      },
    );
  }
}

// ---------------------------------
// タイル: キー名（太字）・値プレビュー
// ---------------------------------
class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.entry,
    required this.value,
    required this.onTap,
  });

  final PreferenceEntry entry;
  final Object? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final valueStr = switch (value) {
      null => 'null',
      final v when v.toString().isEmpty => '(empty)',
      final v => v.toString(),
    };

    final isNullOrEmpty = value == null || value.toString().isEmpty;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        entry.key,
        style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          valueStr,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyMedium?.copyWith(
            color: isNullOrEmpty
                ? colorScheme.onSurfaceVariant
                : colorScheme.onSurface,
            fontStyle: isNullOrEmpty ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
