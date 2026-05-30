import 'package:flutter/material.dart';
import 'package:momeo/pages/console/console_detail_page.dart';
import 'package:momeo/pages/console/sections/storage/storage_shared_preferences_section.dart';

// ---------------------------------
// データ定義
// ---------------------------------

class _Item {
  final String title;
  final Widget body;
  const _Item({required this.title, required this.body});
}

class _Section {
  final String title;
  final List<_Item> items;
  const _Section({required this.title, required this.items});
}

// セクションとアイテムの対応をここで一元管理する
const _sections = [
  _Section(title: 'Storage', items: [
    _Item(title: 'SharedPreferences', body: StorageSharedPreferencesSection()),
  ]),
];

// ---------------------------------
// ページ
// ---------------------------------

class ConsolePage extends StatelessWidget {
  const ConsolePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Console'),
      ),
      body: CustomScrollView(
        slivers: [
          for (final section in _sections) ...[
            // ---------------------------------
            // セクションヘッダー
            // ---------------------------------
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(
                  section.title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        letterSpacing: 1.2,
                      ),
                ),
              ),
            ),
            // ---------------------------------
            // アイテム一覧
            // ---------------------------------
            if (section.items.isEmpty)
              const SliverToBoxAdapter(child: SizedBox.shrink())
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = section.items[index];
                    return ListTile(
                      title: Text(item.title),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ConsoleDetailPage(
                              title: item.title,
                              body: item.body,
                            ),
                          ),
                        );
                      },
                    );
                  },
                  childCount: section.items.length,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
