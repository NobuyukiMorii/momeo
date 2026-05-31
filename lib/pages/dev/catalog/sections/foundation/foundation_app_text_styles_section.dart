import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_text_styles.dart';

class FoundationAppTextStylesSection extends StatelessWidget {
  const FoundationAppTextStylesSection({super.key});

  // ---------------------------------
  // ヘルパー
  // ---------------------------------

  // TextStyle のプロパティを "32px · w700 · h1.25" 形式の文字列にまとめる
  String _spec(TextStyle style) {
    final fontSize = style.fontSize != null ? '${style.fontSize!.toInt()}px' : '';
    final weight = style.fontWeight != null ? 'w${style.fontWeight!.value}' : '';
    final height = style.height != null ? 'h${style.height!.toStringAsFixed(2)}' : '';
    return [fontSize, weight, height].where((s) => s.isNotEmpty).join(' · ');
  }

  // ---------------------------------
  // ビルド
  // ---------------------------------

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: AppTextStyles.entries.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        // ---------------------------------
        // AppTextStyles.entries から index 番目の (name, style) を取り出す
        // ---------------------------------
        final (name, style) = AppTextStyles.entries[index];

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------------------------------
              // 実際のスタイルを適用してトークン名を表示
              // ---------------------------------
              Text(name, style: style),
              // ---------------------------------
              // 上下の間隔
              // ---------------------------------
              const SizedBox(height: 4),
              // ---------------------------------
              // フォントスペック（TextStyle のプロパティから生成）
              // ---------------------------------
              Text(
                _spec(style),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
