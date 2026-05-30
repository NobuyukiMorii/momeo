import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/widgets/animated_text_sequence.dart';

class WidgetsAnimatedTextSequenceSection extends StatelessWidget {
  const WidgetsAnimatedTextSequenceSection({super.key});

  // ---------------------------------
  // ビルド
  // ---------------------------------

  @override
  Widget build(BuildContext context) {
    const items = [
      (
        label: 'スプラッシュ（デフォルト設定）',
        texts: ['momeo', 'Open. Speak. Saved.', 'Auto-start', 'Auto-stop'],
      ),
    ];

    // ---------------------------------
    // リストビュー
    // ---------------------------------

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 24),
      itemBuilder: (context, index) {
        final item = items[index];

        // ---------------------------------
        // カラム
        // ---------------------------------

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 60,
              child: DefaultTextStyle(
                style: AppTextStyles.headline.copyWith(
                  color: AppColors.onSurface,
                ),
                child: AnimatedTextSequence(
                  key: ValueKey(item.label),
                  texts: item.texts,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
