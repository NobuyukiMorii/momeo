import 'package:flutter/material.dart';
import 'package:momeo/widgets/content_slide_transition.dart';

// ---------------------------------
// contentKey が変わったら、progress を 0→1 に動かして
// ContentSlideTransition にスライドアニメーションをさせるウィジェット。
// ---------------------------------
class ContentSlideSwitcher extends StatefulWidget {
  const ContentSlideSwitcher({
    super.key,
    required this.contentKey,
    required this.child,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  // 中身の同一性を識別する値。前回と異なる値になった時だけスライドが起きる
  final Object contentKey;

  // 中身として表示するウィジェット
  final Widget child;

  // スライドアニメーションの時間
  final Duration animationDuration;

  @override
  State<ContentSlideSwitcher> createState() => _ContentSlideSwitcherState();
}

class _ContentSlideSwitcherState extends State<ContentSlideSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // 直近に要求された contentKey（スライド中でも要求が来た時点で更新する）
  late Object _contentKey;

  // スライドで退場中の中身（null の間は静止表示）
  Widget? _outgoingChild;

  // 中身を切り替えた回数。スライドの前後で child の要素を同一視するためのキーに使う
  int _generation = 0;

  @override
  void initState() {
    super.initState();

    _contentKey = widget.contentKey;

    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ---------------------------------
  // contentKey の変化を検知してスライドを起動する（child だけの変化はそのまま build に流れる）
  // ---------------------------------
  @override
  void didUpdateWidget(covariant ContentSlideSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.contentKey == _contentKey) return;
    _contentKey = widget.contentKey;

    // すでにスライド中なら、アニメーションはやり直さない（行き先は build が常に最新の child を使う）
    if (_outgoingChild != null) return;

    // 退場側の中身をこの時点のもので固定してスライド開始
    _outgoingChild = oldWidget.child;
    _generation++;

    _controller.forward(from: 0).then((_) {
      if (!mounted) return;

      // アニメーション完了 → 静止状態に戻す（以降は widget.child がそのまま表示される）
      setState(() {
        _outgoingChild = null;
      });
      _controller.reset();
    });
  }

  // ---------------------------------
  // ビルド
  // ---------------------------------
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final outgoing = _outgoingChild;

        // 世代番号をキーにして、スライドで登場した child を完了後も同じ要素として保つ
        final incoming = KeyedSubtree(
          key: ValueKey(_generation),
          child: widget.child,
        );

        if (outgoing == null) {
          return ContentSlideTransition(current: incoming);
        }

        return ContentSlideTransition(
          current: KeyedSubtree(key: ValueKey(_generation - 1), child: outgoing),
          next: incoming,
          progress: _controller.value,
        );
      },
    );
  }
}
