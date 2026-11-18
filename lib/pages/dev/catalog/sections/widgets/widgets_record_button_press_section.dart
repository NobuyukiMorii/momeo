import 'package:flutter/material.dart';
import 'package:momeo/widgets/record_button_press.dart';

// ============================================================
// RecordButtonPress の動作確認セクション（準備ゲートの録音ボタン）
// ============================================================

class WidgetsRecordButtonPressSection extends StatefulWidget {
  const WidgetsRecordButtonPressSection({super.key});

  @override
  State<WidgetsRecordButtonPressSection> createState() =>
      _WidgetsRecordButtonPressSectionState();
}

class _WidgetsRecordButtonPressSectionState
    extends State<WidgetsRecordButtonPressSection> {
  // 押すたびに増やし、キーを変えて押される演出を最初から再生し直す
  int _replayCount = 0;

  // 輪の進み具合の見本で使う割合
  double _ringProgress = 0.3;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '「もう一度」で押される演出を再生し直せます。'
          '右は待ち画面で使う、動かさない版です。',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            RecordButtonPress(key: ValueKey(_replayCount)),
            const RecordButtonPress(playsPress: false),
          ],
        ),
        const SizedBox(height: 24),
        Center(
          child: OutlinedButton(
            onPressed: () => setState(() => _replayCount++),
            child: const Text('もう一度'),
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'ダウンロードの進み具合（輪が12時の位置から時計回りに伸びる）',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 16),
        Center(
          child: RecordButtonPress(
            playsPress: false,
            ringProgress: _ringProgress,
          ),
        ),
        Slider(
          value: _ringProgress,
          onChanged: (value) => setState(() => _ringProgress = value),
        ),
      ],
    );
  }
}
