import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_radius.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/widgets/activity_dots_text.dart';
import 'package:momeo/widgets/pressable_scale.dart';
import 'package:momeo/widgets/typewriter_text.dart';
import 'package:momeo/widgets/voice_icon.dart';

// カードの上に少しの間だけ出す一言（長押しでコピーした直後）
const _copyNoticeLabel = 'クリップボードにコピーしました';

class VoiceCard extends StatelessWidget {
  const VoiceCard({
    super.key,
    required this.text,
    this.isListening = false,
    this.expectsMore = false,
    this.dateTime,
    this.typeIn = false,
    this.typeFrom = 0,
    this.onTypingComplete,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.showCopyNotice = false,
  });

  final String text;
  final bool isListening;

  // このカードにまだ続きが入るか
  final bool expectsMore;

  final String? dateTime;

  // 選択中はカードの枠線が太くなる
  final bool selected;

  // カード本体をタップしたときの通知（選択の切り替えに使う）。
  // null ならタップを受け付けない
  final VoidCallback? onTap;

  // カード本体を長押ししたときの通知（このカード1枚のコピーに使う）。
  // 選択の切り替えとは別の結果になるので、長押しは既定の 500ms のまま扱う
  final VoidCallback? onLongPress;

  // コピー直後に、カードの上へ一言だけ出す
  final bool showCopyNotice;

  // 確定演出: テキストを1文字ずつ素早くタイピング表示する
  final bool typeIn;

  // タイピングを始める本文上の位置
  final int typeFrom;

  // タイピング演出を使い切ったときの通知（演出の使い捨てに使う）
  final VoidCallback? onTypingComplete;

  // 枠線の太さ（通常時・選択中）
  static const _borderWidth = 1.5;
  static const _selectedBorderWidth = 3.0;

  // 本文の文字の大きさ
  static const _textFontSize = 13.0;

  // 本文と、続きを待つドットとの間隔
  static final _trailingDotsGap = _textFontSize * AppTextStyles.caption.height!;

  // 日時の文字の大きさ
  static const _dateTimeFontSize = 10.0;

  // コピーの知らせの文字の大きさ（日時よりわずかに大きい程度に留める）
  static const _copyNoticeFontSize = 10.0;

  @override
  Widget build(BuildContext context) {
    // 選択で枠線が太くなるぶん padding を減らし、コンテンツの位置と幅を固定する
    final borderWidth = selected ? _selectedBorderWidth : _borderWidth;
    final contentPadding = AppSpacing.l - (borderWidth - _borderWidth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---------------------------------
        // コピーの通知
        // ---------------------------------
        SizedOverflowBox(
          size: const Size(double.infinity, 0),
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Opacity(
              opacity: showCopyNotice ? 1.0 : 0.0,
              child: Text(
                _copyNoticeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.micro.copyWith(
                  fontSize: _copyNoticeFontSize,
                  color: AppColors.onSurface,
                ),
              ),
            ),
          ),
        ),
        // ---------------------------------
        // カード本体
        // ---------------------------------
        PressableScale(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(contentPadding),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.l),
              border: Border.all(
                color: AppColors.onSurface,
                width: borderWidth,
              ),
            ),
            // テキストが空のリスニング中は、左端のドットの増減で処理中の気配を出す
            child: isListening && text.isEmpty
                ? _buildListeningDots()
                : Row(
                    children: [
                      if (isListening) ...[
                        const VoiceIcon(),
                        const SizedBox(width: AppSpacing.l),
                      ],
                      Expanded(child: _buildBody()),
                    ],
                  ),
          ),
        ),
        // 日時はレイアウト上の高さを 0 として扱い、カードの下へはみ出させて描く。
        // カードの高さが日時の有無で変わらなくなるので、日時が出入りしてもずれない
        SizedOverflowBox(
          size: const Size(double.infinity, 0),
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            // 日時の出入りはフェードで繋ぐ（話し始めてすぐ出るので、本文は待たない）
            child: AnimatedOpacity(
              opacity: dateTime != null ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: Text(
                dateTime ?? '',
                style: AppTextStyles.micro.copyWith(
                  fontSize: _dateTimeFontSize,
                  color: AppColors.onSurface,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------
  // 本文
  // ---------------------------------
  Widget _buildBody() {
    final body = TypewriterText(
      text,
      enabled: typeIn,
      typeFrom: typeFrom,
      style: AppTextStyles.caption.copyWith(
        fontSize: _textFontSize,
        color: AppColors.onSurface,
      ),
      onFinished: onTypingComplete,
    );

    // 続きが入らないカードは本文だけで足りる
    if (!expectsMore) return body;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        body,
        SizedBox(height: _trailingDotsGap),
        _buildListeningDots(),
      ],
    );
  }

  // ---------------------------------
  // 聞いている気配を出すドットのアニメーション
  // ---------------------------------
  Widget _buildListeningDots() {
    return DefaultTextStyle(
      style: AppTextStyles.caption.copyWith(
        fontSize: _textFontSize,
        color: AppColors.onSurfaceVariant,
      ),
      child: const ActivityDotsText('', maxDotCount: 10),
    );
  }
}
