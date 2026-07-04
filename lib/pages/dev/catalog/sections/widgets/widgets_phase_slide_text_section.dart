import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/pages/preparation_gate_page.dart';
import 'package:momeo/widgets/phase_slide_text.dart';

// ============================================================
// PhaseSlideText の動作確認セクション
// ============================================================

class WidgetsPhaseSlideTextSection extends StatefulWidget {
  const WidgetsPhaseSlideTextSection({super.key});

  @override
  State<WidgetsPhaseSlideTextSection> createState() =>
      _WidgetsPhaseSlideTextSectionState();
}

class _WidgetsPhaseSlideTextSectionState
    extends State<WidgetsPhaseSlideTextSection> {
  PreparationPhase _phase = PreparationPhase.gettingReady;
  int _percent = 0;

  String get _text {
    switch (_phase) {
      case PreparationPhase.gettingReady:
        return 'Getting ready';
      case PreparationPhase.downloading:
        return 'Downloading $_percent%';
      case PreparationPhase.almostThere:
        return 'Almost there';
      case PreparationPhase.retrying:
        return 'Retrying';
      case PreparationPhase.tryRestarting:
        return 'Try restarting';
    }
  }

  void _selectPhase(PreparationPhase phase) {
    setState(() {
      _phase = phase;
      if (phase == PreparationPhase.downloading) _percent = 0;
    });
  }

  // phase は変えずに%だけ進める → スライドせずその場で更新されるはず
  void _advancePercent() {
    setState(() {
      _percent = (_percent + 10).clamp(0, 100);
    });
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
          'フェーズボタンでスライド切り替えを、「%を進める」で同じフェーズ内の'
          'その場更新（スライドしない）を確認できます。',
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
            child: PhaseSlideText(phase: _phase, text: _text),
          ),
        ),
        const SizedBox(height: 16),

        // ---------------------------------
        // フェーズボタンと%進めるボタン（縦並び・横幅いっぱい）
        // FilledButton はテーマ上ピル形状で横パディングが0のため、
        // 横幅いっぱいにしないと文字が丸角に見切れる
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
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _phase == PreparationPhase.downloading
                ? _advancePercent
                : null,
            child: const Text('%を進める'),
          ),
        ),
      ],
    );
  }
}
