import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_radius.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/widgets/voice_icon.dart';

class VoiceCard extends StatelessWidget {
  const VoiceCard({
    super.key,
    required this.text,
    this.isListening = false,
    this.dateTime,
  });

  final String text;
  final bool isListening;
  final String? dateTime;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---------------------------------
        // カード本体
        // ---------------------------------
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.l),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.l),
          ),
          child: Row(
            children: [
              // ---------------------------------
              // VoiceIcon（認識中のみ表示）
              // ---------------------------------
              if (isListening) ...[
                const VoiceIcon(),
                const SizedBox(width: AppSpacing.l),
              ],

              // ---------------------------------
              // テキスト
              // ---------------------------------
              Expanded(
                child: Text(
                  text,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ---------------------------------
        // 日時表示（指定がある場合のみ）
        // ---------------------------------
        if (dateTime != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              dateTime!,
              style: AppTextStyles.micro.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
