import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/widgets/animated_text_sequence.dart';
import 'package:momeo/widgets/intro_setting_layout.dart';

class WidgetsIntroSettingLayoutSection extends StatelessWidget {
  const WidgetsIntroSettingLayoutSection({super.key});

  // ---------------------------------
  // ビルド
  // ---------------------------------

  @override
  Widget build(BuildContext context) {
    // ---------------------------------
    // テキスト見出しのスタイル（title が String の場合に使う）
    // ---------------------------------
    final headlineStyle = AppTextStyles.headline.copyWith(
      color: AppColors.onSurface,
    );

    // ---------------------------------
    // リストアイテムの設定
    // ---------------------------------
    final variations = [
      (
        label: 'アニメーションテキスト',
        step: null,
        title: DefaultTextStyle(
          style: headlineStyle,
          child: const AnimatedTextSequence(
            texts: ['momeo', 'Open. Speak. Saved.', 'Auto-start', 'Auto-stop'],
          ),
        ) as Widget,
        actionLabel: null,
      ),
      (
        label: 'ステップ + ボタンあり',
        step: '1/2',
        title: Text('Allow Microphone Access', style: headlineStyle) as Widget,
        actionLabel: 'allow',
      ),
      (
        label: 'ステップ + ボタンあり',
        step: '2/2',
        title: Text('Allow Speech Recognition', style: headlineStyle) as Widget,
        actionLabel: 'allow',
      ),
      (
        label: 'ステップ + ボタンあり',
        step: '1/2',
        title: Text('Allow Microphone Access', style: headlineStyle) as Widget,
        actionLabel: 'Open Settings',
      ),
      (
        label: 'テキストのみ',
        step: null,
        title: Text('Allow Microphone Access\nNot Available', style: headlineStyle) as Widget,
        actionLabel: null,
      ),
    ];

    // ---------------------------------
    // リストビュー
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
