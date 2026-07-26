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
            texts: [
              '時の流れの中で生まれ',
              '薄れ消えゆく思考を',
              'そっと残すために',
              'ただ話しかけるだけ',
              'momeo',
            ],
          ),
        ) as Widget,
        actionLabel: null,
      ),
      (
        label: 'ステップ + ボタンあり',
        step: '1/2',
        title: Text('音声を認識するためにマイクを使います', style: headlineStyle) as Widget,
        actionLabel: '許可する',
      ),
      (
        label: 'ステップ + ボタンあり',
        step: '1/2',
        title: Text('設定からマイクの使用を許可してください', style: headlineStyle) as Widget,
        actionLabel: '設定を開く',
      ),
      (
        label: 'テキストのみ',
        step: null,
        title: Text('この端末では\nマイクを使えません', style: headlineStyle) as Widget,
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
