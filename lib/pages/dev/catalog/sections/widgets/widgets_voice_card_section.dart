import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/widgets/voice_card.dart';

class WidgetsVoiceCardSection extends StatelessWidget {
  const WidgetsVoiceCardSection({super.key});

  // ---------------------------------
  // ビルド
  // ---------------------------------

  @override
  Widget build(BuildContext context) {

    // ---------------------------------
    // リストアイテムの設定
    // ---------------------------------
    const items = [
      (label: 'リスニング中インジケーター（テキストなし・左端にドット）', text: '', isListening: true, dateTime: null),
      (label: '認識中（VoiceIcon 付き）', text: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit.', isListening: true, dateTime: null),
      (label: '確定済み', text: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.', isListening: false, dateTime: null),
      (label: '日時付き', text: 'Lorem ipsum dolor sit amet.', isListening: false, dateTime: '2026/01/15 14:30'),
    ];

    // ---------------------------------
    // リストビュー
    // ---------------------------------
    return Container(
      color: AppColors.outline,
      child: ListView.separated(
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
              // ---------------------------------
              // ラベル
              // ---------------------------------
              Text(
                item.label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(height: 8),
              // ---------------------------------
              // カード
              // ---------------------------------
              VoiceCard(
                text: item.text,
                isListening: item.isListening,
                dateTime: item.dateTime,
              ),
            ],
          );
        },
      ),
    );
  }
}
