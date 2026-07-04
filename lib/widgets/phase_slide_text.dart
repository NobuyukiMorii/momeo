import 'package:flutter/material.dart';
import 'package:momeo/widgets/text_slide_transition.dart';

// ---------------------------------
// PhaseSlideText — phase 変化時のみスライドし、同一 phase 内の更新は即時置換する。
// ---------------------------------
class PhaseSlideText extends StatefulWidget {
  const PhaseSlideText({
    super.key,
    required this.phase,
    required this.text,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  // 現在のフェーズを識別する値。前回と異なる値になった時だけスライドが起きる。
  final Object phase;

  // 実際に表示するテキスト。同じ phase のままでの変化はその場で更新される。
  final String text;

  // スライドアニメーションの時間（AnimatedTextSequence と揃える）
  final Duration animationDuration;

  @override
  State<PhaseSlideText> createState() => _PhaseSlideTextState();
}

class _PhaseSlideTextState extends State<PhaseSlideText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // 直近に要求された phase（スライド中でも要求が来た時点で更新する）
  late Object _phase;

  // 静止状態で表示中のテキスト
  late String _currentText;

  // スライドで登場中の次のテキスト（null の間は静止表示）
  String? _nextText;

  @override
  void initState() {
    super.initState();

    _phase = widget.phase;
    _currentText = widget.text;

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
  // 外から渡された phase・text の変化を検知し、スライドの起動 or その場更新を判断する
  // ---------------------------------
  @override
  void didUpdateWidget(covariant PhaseSlideText oldWidget) {
    super.didUpdateWidget(oldWidget);

    final isPhaseChanged = widget.phase != _phase;
    _phase = widget.phase;

    if (isPhaseChanged) {
      if (_nextText == null) {
        _startTransition(widget.text);
      } else {
        // すでにスライド中に次の phase が来た場合は、
        // アニメーションをやり直さず行き先のテキストだけ最新化する
        setState(() {
          _nextText = widget.text;
        });
      }
      return;
    }

    // phase は変わっていない
    if (_nextText != null) {
      // スライド中に同じ phase のテキストが変わった（例: DL%の更新）→ 行き先を差し替えるだけ
      if (widget.text != _nextText) {
        setState(() {
          _nextText = widget.text;
        });
      }
    } else if (widget.text != _currentText) {
      // 静止中にテキストだけ変わった → スライドさせずその場で即時更新
      setState(() {
        _currentText = widget.text;
      });
    }
  }

  // ---------------------------------
  // スライドを起動する
  // ---------------------------------
  void _startTransition(String nextText) {
    setState(() {
      _nextText = nextText;
    });

    _controller.forward(from: 0).then((_) {
      if (!mounted) return;

      // アニメーション完了 → 次のテキストに切り替えて静止状態に戻す
      setState(() {
        _currentText = _nextText!;
        _nextText = null;
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
        return TextSlideTransition(
          currentText: _currentText,
          nextText: _nextText,
          progress: _controller.value,
        );
      },
    );
  }
}
