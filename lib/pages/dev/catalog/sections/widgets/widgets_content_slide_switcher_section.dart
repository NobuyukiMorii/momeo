import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/pages/preparation_gate_page.dart';
import 'package:momeo/pages/splash_page.dart';
import 'package:momeo/widgets/activity_dots_text.dart';
import 'package:momeo/widgets/content_slide_switcher.dart';

// ============================================================
// ContentSlideSwitcher の動作確認セクション
// ============================================================

class WidgetsContentSlideSwitcherSection extends StatefulWidget {
  const WidgetsContentSlideSwitcherSection({super.key});

  @override
  State<WidgetsContentSlideSwitcherSection> createState() =>
      _WidgetsContentSlideSwitcherSectionState();
}

class _WidgetsContentSlideSwitcherSectionState
    extends State<WidgetsContentSlideSwitcherSection> {
  PreparationPhase _phase = PreparationPhase.loading;

  // ---------------------------------
  // 選択中フェーズの中身
  // ---------------------------------
  Widget get _content {
    switch (_phase) {
      case PreparationPhase.loading:
        return const Text(splashAppName);
      case PreparationPhase.retrying:
        return const ActivityDotsText('再試行しています');
      case PreparationPhase.tryRestarting:
        return const Text('アプリを再起動してください');
      case PreparationPhase.unsupported:
        return const Text('この端末では使えません');
      case PreparationPhase.downloadingLanguage:
        return const ActivityDotsText('言語のモデルをダウンロードしています');
    }
  }

  void _selectPhase(PreparationPhase phase) {
    setState(() => _phase = phase);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---------------------------------
        // 説明テキスト
        // ---------------------------------
        const Text(
          'フェーズボタンでスライド切り替えを確認できます。'
          '処理中フェーズはドットが動き続けます。',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 16),

        // ---------------------------------
        // フェーズテキスト
        // ---------------------------------
        Container(
          height: 60,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DefaultTextStyle(
            style: AppTextStyles.headline.copyWith(color: AppColors.onSurface),
            child: ContentSlideSwitcher(contentKey: _phase, child: _content),
          ),
        ),
        const SizedBox(height: 16),

        // ---------------------------------
        // フェーズボタン
        // ---------------------------------
        for (final phase in PreparationPhase.values) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _selectPhase(phase),
              child: Text(phase.name),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
