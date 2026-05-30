import 'package:flutter/material.dart';

// ---------------------------------
// AnimatedTextSequence — 設定（外から受け取る値: texts, displayDuration, animationDuration, onFinished）
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
    // 親の DefaultTextStyle を継承する
    final textStyle = DefaultTextStyle.of(context).style;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // ---------------------------------
        // 静止状態: 現在のテキストをそのまま表示
        // ---------------------------------
        if (!_isTransitioning) {
          return Text(widget.texts[_currentIndex], style: textStyle);
        }

        // ---------------------------------
        // スライドアニメーション中: 現テキストが左へ、次テキストが右から同時に動く
        // ---------------------------------

        // コンテナ幅を基準にピクセルで移動量を計算する
        return LayoutBuilder(
          builder: (context, constraints) {
            final containerWidth = constraints.maxWidth;

            // 現在のテキスト: 中央 → 左へ退場（コンテナ幅分だけ移動）
            final currentOffset = -_controller.value * containerWidth;

            // 次のテキスト: 右 → 中央へ登場（コンテナ幅分だけ移動）
            final nextOffset = (1.0 - _controller.value) * containerWidth;

            return Stack(
              children: [
                // 現在のテキスト（左へ退場）
                Transform.translate(
                  offset: Offset(currentOffset, 0),
                  child: Text(widget.texts[_currentIndex], style: textStyle),
                ),

                // 次のテキスト（右から登場）
                Transform.translate(
                  offset: Offset(nextOffset, 0),
                  child: Text(widget.texts[_currentIndex + 1], style: textStyle),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
