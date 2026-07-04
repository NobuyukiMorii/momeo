import 'package:flutter/material.dart';
import 'package:momeo/widgets/text_slide_transition.dart';

// ---------------------------------
// AnimatedTextSequence — 一定時間ごとに次のテキストへ進める時間駆動のラッパー
// スライドの描画は TextSlideTransition に委譲する
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
// State — 内部で変化するデータ（インデックス、アニメーション）と描画
// ---------------------------------
class _AnimatedTextSequenceState extends State<AnimatedTextSequence>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // 現在表示中のテキストのインデックス
  int _currentIndex = 0;

  // スライドアニメーション中かどうか
  bool _isTransitioning = false;

  // ---------------------------------
  // 初回表示時にアニメーションを準備・次のテキストをスケジュール
  // ---------------------------------
  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );

    // 最初のテキストはアニメーションなしで即表示し、次の切り替えをスケジュール
    _scheduleNext();
  }

  // ---------------------------------
  // 画面から消える時にアニメーションを破棄
  // ---------------------------------
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ---------------------------------
  // 次のテキストへの切り替えをスケジュール
  // ---------------------------------
  void _scheduleNext() {
    Future.delayed(widget.displayDuration, () {
      if (!mounted) return;

      // 最後のテキストだった場合は完了コールバックを呼ぶ
      if (_currentIndex >= widget.texts.length - 1) {
        widget.onFinished?.call();
        return;
      }

      // スライドアニメーション開始
      setState(() {
        _isTransitioning = true;
      });

      _controller.forward(from: 0).then((_) {
        if (!mounted) return;

        // アニメーション完了 → 次のテキストに切り替えて静止状態に戻す
        setState(() {
          _currentIndex++;
          _isTransitioning = false;
        });

        _controller.reset();
        _scheduleNext();
      });
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
          currentText: widget.texts[_currentIndex],
          nextText: _isTransitioning
              ? widget.texts[_currentIndex + 1]
              : null,
          progress: _controller.value,
        );
      },
    );
  }
}
