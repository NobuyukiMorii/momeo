import 'package:flutter/material.dart';

// ---------------------------------
// DownloadingProgressText — DL進捗を「Downloading n%」で表示するテキスト。
// 等幅数字（tabular figures）で、% の位置が数字の変化で揺れないようにする（桁上がり時のみ動く）。
// ---------------------------------
class DownloadingProgressText extends StatelessWidget {
  const DownloadingProgressText({super.key, required this.percent});

  // 表示する進捗（0〜100）
  final int percent;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Downloading $percent%',
      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
    );
  }
}
