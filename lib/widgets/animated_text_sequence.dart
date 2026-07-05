import 'package:flutter/material.dart';
import 'package:momeo/widgets/content_slide_switcher.dart';

// ---------------------------------
// テキストのリストをスライドアニメーションで順番に表示するウィジェット
// ---------------------------------
class AnimatedTextSequence extends StatefulWidget {
  const AnimatedTextSequence({
    super.key,
    required this.texts,
    this.displayDuration = const Duration(milliseconds: 1500),
    this.animationDuration = const Duration(milliseconds: 300),
    this.onFinished,
  });

  // 順番に表示するテキストのリスト
  final List<String> texts;

  // 各テキストの表示時間
  final Duration displayDuration;

  // スライドアニメーションの時間
  final Duration animationDuration;

  // 全テキストの表示が終わった時に呼ばれるコールバック
  final VoidCallback? onFinished;

  @override
  State<AnimatedTextSequence> createState() => _AnimatedTextSequenceState();
}

// ---------------------------------
// State — タイマーでインデックスを進めるだけ（スライド演出は ContentSlideSwitcher に任せる）
// ---------------------------------
class _AnimatedTextSequenceState extends State<AnimatedTextSequence> {
  // 現在表示中のテキストのインデックス
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();

    // 最初のテキストはアニメーションなしで即表示し、次の切り替えをスケジュール
    _scheduleNext(afterSlide: false);
  }

  // ---------------------------------
  // 次のテキストへの切り替えをスケジュール
  // ---------------------------------
  void _scheduleNext({required bool afterSlide}) {
    // スライド直後は、退場アニメーションの分も待ってから表示時間を数える
    final delay = afterSlide
        ? widget.animationDuration + widget.displayDuration
        : widget.displayDuration;

    Future.delayed(delay, () {
      if (!mounted) return;

      // 最後のテキストだった場合は完了コールバックを呼ぶ
      if (_currentIndex >= widget.texts.length - 1) {
        widget.onFinished?.call();
        return;
      }

      // インデックスを進める → ContentSlideSwitcher がスライドを開始する
      setState(() {
        _currentIndex++;
      });

      _scheduleNext(afterSlide: true);
    });
  }

  // ---------------------------------
  // ビルド
  // ---------------------------------
  @override
  Widget build(BuildContext context) {
    return ContentSlideSwitcher(
      contentKey: _currentIndex,
      animationDuration: widget.animationDuration,
      child: Text(widget.texts[_currentIndex]),
    );
  }
}
