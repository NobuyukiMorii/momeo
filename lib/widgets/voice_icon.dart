import 'dart:math';
import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_radius.dart';

// ---------------------------------
// VoiceIcon — 設定（外から受け取る値: size, isAnimating）
// ---------------------------------
class VoiceIcon extends StatefulWidget {
  const VoiceIcon({
    super.key,
    this.isAnimating = true,
    this.size = 32.0,
  });

  final bool isAnimating;
  final double size;

  @override
  State<VoiceIcon> createState() => _VoiceIconState();
}

// ---------------------------------
// State — 内部で変化するデータ（アニメーション）と描画
// ---------------------------------
class _VoiceIconState extends State<VoiceIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // 棒の本数
  static const _barCount = 9;

  // 各棒の動きのタイミングのずれ（値が大きいほど遅れて動く）
  static const _phaseOffsets = [0.0, 0.7, 1.4, 2.1, 2.8, 3.5, 4.2, 4.9, 5.6];

  // 棒の静止時の高さ比率（アニメーション停止時）
  static const _restHeights = [0.3, 0.5, 0.7, 0.9, 1.0, 0.9, 0.7, 0.5, 0.3];

  // ---------------------------------
  // 初回表示時にアニメーションを準備・開始
  // ---------------------------------
  @override
  void initState() {
    super.initState();

    // アニメーションコントローラーを初期化
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // アニメーションを開始
    if (widget.isAnimating) {
      _controller.repeat();
    }
  }

  // ---------------------------------
  // isAnimating の変化に応じてアニメーションを開始・停止
  // ---------------------------------
  @override
  void didUpdateWidget(VoiceIcon oldWidget) {
    super.didUpdateWidget(oldWidget);

    // アニメーションを開始・停止
    if (widget.isAnimating && !oldWidget.isAnimating) {
      // アニメーションを開始
      _controller.repeat();
    } else if (!widget.isAnimating && oldWidget.isAnimating) {
      // アニメーションを停止
      _controller.stop();
    }
  }

  // ---------------------------------
  // 画面から消える時にアニメーションを破棄
  // ---------------------------------
  @override
  void dispose() {
    // アニメーションコントローラーを破棄
    _controller.dispose();
    super.dispose();
  }

  // ---------------------------------
  // 各棒の高さ比率を計算
  // ---------------------------------
  double _barHeightRatio(int index) {

    // アニメーション停止時は静止時の高さを返す
    if (!widget.isAnimating) return _restHeights[index];

    // アニメーション中は sin カーブに沿って高さを計算
    final phase = _controller.value * 2 * pi + _phaseOffsets[index];

    // 0.2 〜 1.0 の範囲で sin カーブに沿って高さを計算
    return 0.2 + 0.8 * ((sin(phase) + 1) / 2);
  }

  // ---------------------------------
  // ビルド
  // ---------------------------------
  @override
  Widget build(BuildContext context) {

    // 棒の幅
    final barWidth = widget.size / (_barCount * 2 - 1);

    // 棒の間隔
    final gap = barWidth;

    // ---------------------------------
    // アニメーションに連動して毎フレーム再描画する
    // ---------------------------------
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {

        // ---------------------------------
        // 9本の縦線を横に並べる
        // ---------------------------------
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(_barCount, (index) {

              // 棒の高さ比率を計算
              final barHeight = widget.size * _barHeightRatio(index);

              // ---------------------------------
              // 1本ずつの縦線（隣との間隔を左側に確保）
              // ---------------------------------
              return Padding(
                padding: EdgeInsets.only(left: index > 0 ? gap : 0),
                child: Container(
                  width: barWidth,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: AppColors.onSurface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
