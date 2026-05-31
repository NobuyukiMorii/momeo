import 'package:flutter/material.dart';

// ConsolePage から title と body を受け取って表示するだけのページ
class ConsoleDetailPage extends StatelessWidget {
  const ConsoleDetailPage({super.key, required this.title, required this.body});

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
