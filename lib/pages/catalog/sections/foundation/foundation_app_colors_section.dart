import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';

class FoundationAppColorsSection extends StatelessWidget {
  const FoundationAppColorsSection({super.key});

  // ---------------------------------
  // ヘルパー
  // ---------------------------------

  // Color → "#RRGGBB" 形式の文字列に変換する
  //
  // toARGB32()  : Color を 32bit 整数に変換 → 0xAARRGGBB
  // toRadixString(16) : 16進数文字列に変換  → "aarrggbb"
  // padLeft(8, '0')   : 8桁になるよう0埋め  → "00rrggbb"（暗い色で桁が足りない場合の対策）
  // substring(2)      : 先頭2文字（AA）を除去 → "rrggbb"
  // toUpperCase()     : 大文字に統一         → "RRGGBB"
  String _toHex(Color color) {
    final hex = color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
    return '#$hex';
  }

  // ---------------------------------
  // ビルド
  // ---------------------------------

  @override
  Widget build(BuildContext context) {

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: AppColors.entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        // ---------------------------------
        // entries[index] は (name, color) のレコード型 → 分解して取り出す
        // ---------------------------------
        final (name, color) = AppColors.entries[index];

        return Row(
          children: [
            // ---------------------------------
            // カラープレビュー（薄色でも視認できるよう outline ボーダーを付与）
            // ---------------------------------
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            // ---------------------------------
            // 左右の間隔
            // ---------------------------------
            const SizedBox(width: 16),
            // ---------------------------------
            // トークン名 + HEX値
            // ---------------------------------
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---------------------------------
                // トークン名
                // ---------------------------------
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                // ---------------------------------
                // HEX値
                // ---------------------------------
                Text(
                  _toHex(color),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
