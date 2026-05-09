import 'package:flutter/material.dart';
import 'package:momeo/widgets/voice_icon.dart';

class WidgetsVoiceIconSection extends StatelessWidget {
  const WidgetsVoiceIconSection({super.key});

  // ---------------------------------
  // ビルド
  // ---------------------------------

  @override
  Widget build(BuildContext context) {
    const items = [
      (label: 'アニメーション中（32px）', size: 32.0, animating: true),
      (label: 'アニメーション中（48px）', size: 48.0, animating: true),
      (label: 'アニメーション中（64px）', size: 64.0, animating: true),
      (label: '停止中（32px）', size: 32.0, animating: false),
    ];

    // ---------------------------------
    // リストビュー
    // ---------------------------------

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 24),
      itemBuilder: (context, index) {

        // ---------------------------------
        // リストアイテム
        // ---------------------------------
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
            Center(
              child: VoiceIcon(
                size: item.size,
                isAnimating: item.animating,
              ),
            ),
          ],
        );
      },
    );
  }
}
