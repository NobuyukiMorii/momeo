import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';

// ---------------------------------
// アプリアイコンと同じ「輪＋黒丸」を出し、黒丸がひとりでに押されたように一度沈んで戻るウィジェット
// 表示されたら一度だけ再生する（繰り返さない）
// OS の起動画面にも同じ姿のボタンを出しているので、フェードインせず最初から表示する
// ---------------------------------
class RecordButtonPress extends StatefulWidget {
  const RecordButtonPress({super.key, this.size = 120, this.playsPress = true});

  // 輪の外径
  final double size;

  // false なら動かさず、押し終わった姿のまま出す（スプラッシュの後ろの待ち画面で使う）
  final bool playsPress;

  @override
  State<RecordButtonPress> createState() => _RecordButtonPressState();
}

class _RecordButtonPressState extends State<RecordButtonPress>
    with SingleTickerProviderStateMixin {
  // アイコンの比率（タイルに対して輪の外径 0.695・線幅 0.035・黒丸 0.48）を外径基準に直した値
  static const _ringWidthRatio = 0.05;
  static const _dotDiameterRatio = 0.69;

  // 押したときに黒丸が縮む大きさ
  static const _pressedDotScale = 0.86;

  late final AnimationController _controller;
  late final Animation<double> _dotScale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // ---------------------------------
    // 再生の流れ: 少し待つ → キュッと沈む → 弾むように戻る
    // weight は 900ms の中での長さ（100 = 100ms）
    // ---------------------------------
    _dotScale = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 450),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: _pressedDotScale,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 100,
      ),
      TweenSequenceItem(tween: ConstantTween(_pressedDotScale), weight: 60),
      TweenSequenceItem(
        tween: Tween(
          begin: _pressedDotScale,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 290,
      ),
    ]).animate(_controller);

    if (widget.playsPress) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ---------------------------------
  // ビルド
  // ---------------------------------
  @override
  Widget build(BuildContext context) {
    final dotDiameter = widget.size * _dotDiameterRatio;

    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 外側の輪（動かない）
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.onSurface,
                width: widget.size * _ringWidthRatio,
              ),
            ),
            child: const SizedBox.expand(),
          ),

          // 中央の黒丸（押されて沈む）
          ScaleTransition(
            scale: _dotScale,
            child: Container(
              width: dotDiameter,
              height: dotDiameter,
              decoration: const BoxDecoration(
                color: AppColors.onSurface,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
