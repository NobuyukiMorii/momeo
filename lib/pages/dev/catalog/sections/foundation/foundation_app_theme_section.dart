import 'package:flutter/material.dart';
import 'package:momeo/pages/dev/catalog/catalog_detail_page.dart';
import 'package:momeo/pages/dev/catalog/sections/foundation/theme/theme_filled_button_page.dart';

// ---------------------------------
// テーマ設定のサブアイテム一覧
// ---------------------------------
const _items = [
  ('FilledButton', ThemeFilledButtonPage()),
];

class FoundationAppThemeSection extends StatelessWidget {
  const FoundationAppThemeSection({super.key});

  // ---------------------------------
  // ビルド
  // ---------------------------------

  @override
  Widget build(BuildContext context) {

    // ---------------------------------
    // リストビュー設定
    // ---------------------------------
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, index) {

        // ---------------------------------
        // リストアイテムのタイトルとボディ
        // ---------------------------------
        final (title, body) = _items[index];

        // ---------------------------------
        // リストタイトルとアイコンを設定
        // ---------------------------------
        return ListTile(
          title: Text(title),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CatalogDetailPage(
                  title: title,
                  body: body,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
