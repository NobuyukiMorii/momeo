import 'package:flutter/material.dart';

// ---------------------------------
// progress で指定された分だけスライドした状態の絵を描くウィジェット。
// 自分では動かない。progress を動かすのは ContentSlideSwitcher。
// ---------------------------------
class ContentSlideTransition extends StatelessWidget {
  const ContentSlideTransition({
    super.key,
    required this.current,
    this.next,
    this.progress = 0.0,
  });

  // 現在表示中の中身
  final Widget current;

  // 次に表示する中身（null の間は静止表示）
  final Widget? next;

  // スライドの進行度（0.0: current が定位置 〜 1.0: next が定位置）
  final double progress;

  @override
  Widget build(BuildContext context) {
    final next = this.next;

    // 静止時もスライド時と同じツリー構造で描く（構造を切り替えると中身の要素が作り直され、内部状態が失われるため）
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerWidth = constraints.maxWidth;

        // current: 定位置 → 左へ退場（静止時は定位置に固定）
        final currentOffset = next == null ? 0.0 : -progress * containerWidth;

        // next: 右 → 定位置へ登場
        final nextOffset = (1.0 - progress) * containerWidth;

        // キーは Stack の直接の子へ引き上げる（スライド完了時に next の要素を current 側へ引き継ぐため）
        return Stack(
          children: [
            Transform.translate(
              key: current.key,
              offset: Offset(currentOffset, 0),
              child: current,
            ),
            if (next != null)
              Transform.translate(
                key: next.key,
                offset: Offset(nextOffset, 0),
                child: next,
              ),
          ],
        );
      },
    );
  }
}
