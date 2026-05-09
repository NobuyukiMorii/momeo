import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_theme.dart';
import 'package:momeo/pages/my_home_page.dart';
import 'package:momeo/pages/catalog/catalog_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: AppTheme.light(),
      home: const RootView(),
    );
  }
}

class RootView extends StatelessWidget {
  const RootView({super.key});

  @override
  Widget build(BuildContext context) {
    return PageView(
      children: const [
        MyHomePage(title: 'Flutter Demo Home Page'),
        CatalogPage(),
      ],
    );
  }
}
