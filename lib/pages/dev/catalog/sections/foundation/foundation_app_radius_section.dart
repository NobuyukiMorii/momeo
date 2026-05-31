import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_radius.dart';

class FoundationAppRadiusSection extends StatelessWidget {
  const FoundationAppRadiusSection({super.key});

  // ---------------------------------
  // ビルド
  // ---------------------------------

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: AppRadius.entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        // ---------------------------------
        // AppRadius.entries から index 番目の (name, radius) を取り出す
        // ---------------------------------
        final (name, radius) = AppRadius.entries[index];

        // ---------------------------------
        // 表示用の角丸値を決定
        // 999dp (pill) はプレビュー矩形に収まらないため表示上は 32dp に丸める
        // ラベルには実際の値を使う
        // ---------------------------------
        final displayRadius = radius > 32 ? 32.0 : radius;

        return Row(
          children: [
            // ---------------------------------
            // トークン名（幅固定でプレビューの開始位置を揃える）
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
            // 角丸プレビュー矩形
            // ---------------------------------
            Container(
              width: 64,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(displayRadius),
              ),
            ),
            const SizedBox(width: 12),
            // ---------------------------------
            // dp値ラベル
            // ---------------------------------
            Text(
              radius > 32 ? '999dp (pill)' : '${radius.toInt()}dp',
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
