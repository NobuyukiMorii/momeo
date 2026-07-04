import 'package:flutter/material.dart';

// ---------------------------------
// TextSlideTransition — progress（0.0〜1.0）に応じて左へ退場・右から登場を描くだけの共通ウィジェット。
// 切り替えタイミングの制御は呼び出し側の責務。
// ---------------------------------
class TextSlideTransition extends StatelessWidget {
  const TextSlideTransition({
    super.key,
    required this.currentText,
    this.nextText,
    this.progress = 0.0,
  });

  // 現在表示中のテキスト
  final String currentText;

  // 次に表示するテキスト（null の間は静止表示）
  final String? nextText;

  // スライドの進行度（0.0: 現テキストが中央 〜 1.0: 次テキストが中央）
  final double progress;

  @override
  Widget build(BuildContext context) {
    // 親の DefaultTextStyle を継承する
    final textStyle = DefaultTextStyle.of(context).style;

    // ---------------------------------
    // 静止状態: 現在のテキストをそのまま表示
    // ---------------------------------
    final nextText = this.nextText;
    if (nextText == null) {
      return Text(currentText, style: textStyle);
    }

    // ---------------------------------
    // スライドアニメーション中: 現テキストが左へ、次テキストが右から同時に動く
    // コンテナ幅を基準にピクセルで移動量を計算する
    // ---------------------------------
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerWidth = constraints.maxWidth;

        // 現在のテキスト: 中央 → 左へ退場（コンテナ幅分だけ移動）
        final currentOffset = -progress * containerWidth;

        // 次のテキスト: 右 → 中央へ登場（コンテナ幅分だけ移動）
        final nextOffset = (1.0 - progress) * containerWidth;

        return Stack(
          children: [
            // 現在のテキスト（左へ退場）
            Transform.translate(
              offset: Offset(currentOffset, 0),
              child: Text(currentText, style: textStyle),
            ),

            // 次のテキスト（右から登場）
            Transform.translate(
              offset: Offset(nextOffset, 0),
              child: Text(nextText, style: textStyle),
            ),
          ],
        );
      },
    );
  }
}
