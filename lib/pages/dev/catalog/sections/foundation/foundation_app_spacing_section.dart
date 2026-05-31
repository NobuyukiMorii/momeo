import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_spacing.dart';

class FoundationAppSpacingSection extends StatelessWidget {
  const FoundationAppSpacingSection({super.key});

  // ---------------------------------
  // ビルド
  // ---------------------------------

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: AppSpacing.entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        // ---------------------------------
        // AppSpacing.entries から index 番目の (name, value) を取り出す
        // ---------------------------------
        final (name, value) = AppSpacing.entries[index];

        return Row(
          children: [
            // ---------------------------------
            // トークン名（幅固定でバーの開始位置を揃える）
            // ---------------------------------
            SizedBox(
              width: 40,
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            // ---------------------------------
            // スケールバー（視認性のため実値の4倍幅で描画）
            // ---------------------------------
            Container(
              width: value * 4,
              height: 24,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            // ---------------------------------
            // dp値ラベル
            // dp = 論理ピクセル（physical px とは別物。デバイス密度に依存しない単位）
            // ---------------------------------
            Text(
              '${value.toInt()}dp',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        );
      },
    );
  }
}
