import 'package:flutter/material.dart';

class ThemeFilledButtonPage extends StatelessWidget {
  const ThemeFilledButtonPage({super.key});

  // ---------------------------------
  // ビルド
  // ---------------------------------

  @override
  Widget build(BuildContext context) {

    // ---------------------------------
    // ボタンのプレビュー
    // ---------------------------------

    const buttons = [
      (label: 'allow', enabled: true),
      (label: 'Open Settings', enabled: true),
      (label: 'Disabled', enabled: false),
    ];

    // ---------------------------------
    // リストビュー設定
    // ---------------------------------
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: buttons.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final (:label, :enabled) = buttons[index];
        return SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: enabled ? () {} : null,
            child: Text(label),
          ),
        );
      },
    );
  }
}
