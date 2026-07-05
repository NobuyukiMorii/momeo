import 'dart:async';

import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/pages/preparation_gate_page.dart';
import 'package:momeo/widgets/activity_dots_text.dart';
import 'package:momeo/widgets/downloading_progress_text.dart';
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
  PreparationPhase _phase = PreparationPhase.gettingReady;
  int _percent = 0;

  // ---------------------------------
  // ダウンロードタイマー
  // ---------------------------------
  Timer? _downloadTimer;

  // ---------------------------------
  // 選択中フェーズの中身
  // ---------------------------------
  Widget get _content {
    switch (_phase) {
      case PreparationPhase.gettingReady:
        return const ActivityDotsText('Getting ready');
      case PreparationPhase.downloading:
        return DownloadingProgressText(percent: _percent);
      case PreparationPhase.almostThere:
        return const ActivityDotsText('Almost there');
      case PreparationPhase.retrying:
        return const ActivityDotsText('Retrying');
      case PreparationPhase.tryRestarting:
        return const Text('Try restarting');
    }
  }

  void _selectPhase(PreparationPhase phase) {
    // ---------------------------------
    // ダウンロードタイマーを止める
    // ---------------------------------
    _downloadTimer?.cancel();

    // ---------------------------------
    // フェーズを更新
    // ---------------------------------
    setState(() {
      _phase = phase;
      if (phase == PreparationPhase.downloading) _percent = 0;
    });

    // ---------------------------------
    // ダウンロードタイマーを開始
    // ---------------------------------
    if (phase == PreparationPhase.downloading) _startDownloadDemo();
  }

  // ---------------------------------
  // ダウンロード率の更新
  // ---------------------------------
  void _startDownloadDemo() {
    _downloadTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        _percent++;
      });
      if (_percent >= 100) timer.cancel();
    });
  }

  @override
  void dispose() {
    _downloadTimer?.cancel();
    super.dispose();
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
          'フェーズボタンでスライド切り替えを確認できます。downloading は 0% から 100% まで'
          '1%ずつ自動で進み、同じフェーズ内はスライドせずその場で更新されます。'
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
