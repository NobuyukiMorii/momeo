import 'package:flutter/material.dart';
import 'package:momeo/widgets/intro_setting_layout.dart';


class WidgetsIntroSettingLayoutSection extends StatelessWidget {

  const WidgetsIntroSettingLayoutSection({super.key});

  // ---------------------------------
  // ビルド
  // ---------------------------------

  @override
  Widget build(BuildContext context) {

    // ---------------------------------
    // リストアイテムの設定
    // ---------------------------------
    const variations = [
      (label: 'ステップ + ボタンあり', step: '1/2', title: 'Allow Microphone Access', actionLabel: 'allow'),
      (label: 'ステップ + ボタンあり', step: '2/2', title: 'Allow Speech Recognition', actionLabel: 'allow'),
      (label: 'ステップ + ボタンあり', step: '1/2', title: 'Allow Microphone Access', actionLabel: 'Open Settings'),
      (label: 'ボタンなし', step: null, title: 'momeo', actionLabel: null),
      (label: 'テキストのみ', step: null, title: 'Allow Microphone Access\nNot Available', actionLabel: null),
    ];

    // ---------------------------------
    // リストビュ
    // ---------------------------------
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: variations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final v = variations[index];
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  body: IntroSettingLayout(
                    step: v.step,
                    title: v.title,
                    actionLabel: v.actionLabel,
                    onAction: v.actionLabel != null ? () {} : null,
                  ),
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(v.label),
          ),
        );
      },
    );
  }
}
