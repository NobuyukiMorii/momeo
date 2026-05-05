import 'package:flutter/material.dart';

// CatalogPage から title と body を受け取って表示するだけのページ
// どのセクションを表示するかは CatalogPage 側で決まる
class CatalogDetailPage extends StatelessWidget {
  const CatalogDetailPage({super.key, required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: body,
    );
  }
}
