import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_radius.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/widgets/activity_dots_text.dart';
import 'package:momeo/widgets/hold_to_copy_effect.dart';
import 'package:momeo/widgets/typewriter_text.dart';
import 'package:momeo/widgets/voice_icon.dart';

class VoiceCard extends StatefulWidget {
  const VoiceCard({
    super.key,
    required this.text,
    this.isListening = false,
    this.dateTime,
    this.typeIn = false,
    this.onTypingComplete,
    this.onCopy,
  });

  final String text;
  final bool isListening;
  final String? dateTime;

  // 長押しの塗りつぶし演出が完了したときの通知（＝テキストコピーの合図）。
  // null なら長押しを受け付けない
  final VoidCallback? onCopy;

  // 確定演出: テキストを1文字ずつ素早くタイピング表示する
  final bool typeIn;

  // タイピング演出を使い切ったときの通知（演出の使い捨てに使う）
  final VoidCallback? onTypingComplete;

  @override
  State<VoiceCard> createState() => _VoiceCardState();
}

class _VoiceCardState extends State<VoiceCard> {
  // 日時のフェードインをタイピングの打ち終わりまで待たせるためのフラグ
  bool _typingFinished = false;

  @override
  void initState() {
    super.initState();
    _typingFinished = !widget.typeIn;
  }

  @override
  void didUpdateWidget(VoiceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 演出が外れた（別のカードに移った）ら日時も即表示に切り替える
    if (!widget.typeIn) _typingFinished = true;
  }

  // タイピングを使い切ったら日時を出し、通知を外へ引き継ぐ
  void _handleTypingFinished() {
    if (mounted) setState(() => _typingFinished = true);
    widget.onTypingComplete?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 長押しで右から左へ黒く塗りつぶし、塗り切ったらコピー
        HoldToCopyEffect(
          borderRadius: AppRadius.l,
          onCopied: widget.onCopy,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.l),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.l),
              border: Border.all(color: AppColors.onSurface, width: 1.5),
            ),
            // テキストが空のリスニング中は、左端のドットの増減で処理中の気配を出す
            child: widget.isListening && widget.text.isEmpty
                ? DefaultTextStyle(
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                    child: const ActivityDotsText('', maxDotCount: 10),
                  )
                : Row(
                    children: [
                      if (widget.isListening) ...[
                        const VoiceIcon(),
                        const SizedBox(width: AppSpacing.l),
                      ],
                      Expanded(
                        child: TypewriterText(
                          widget.text,
                          enabled: widget.typeIn,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.onSurface,
                          ),
                          onFinished: _handleTypingFinished,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        // 日時はタイピングが終わってからフェードイン
        if (widget.dateTime != null) ...[
          const SizedBox(height: AppSpacing.xs),
          AnimatedOpacity(
            opacity: _typingFinished ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                widget.dateTime!,
                style: AppTextStyles.micro.copyWith(color: AppColors.onSurface),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
