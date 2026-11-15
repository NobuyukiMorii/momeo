import 'dart:math';

import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';

// ---------------------------------
// アプリアイコンと同じ「輪＋黒丸」を出し、黒丸がひとりでに押されたように一度沈んで戻るウィジェット
// 表示されたら一度だけ再生する（繰り返さない）
// OS の起動画面にも同じ姿のボタンを出しているので、フェードインせず最初から表示する
// ringProgress を渡すと、外側の輪が12時の位置から時計回りにその割合だけ伸びた姿になる（ダウンロードの進み具合）
// ---------------------------------
class RecordButtonPress extends StatefulWidget {
  const RecordButtonPress({
    super.key,
    this.size = 120,
    this.playsPress = true,
    this.ringProgress,
  });

  // 輪の外径
  final double size;

  // false なら動かさず、押し終わった姿のまま出す（スプラッシュの後ろの待ち画面で使う）
  final bool playsPress;

  // 輪を伸ばす割合（0.0〜1.0）。null なら一周つながった輪を出す
  final double? ringProgress;

  @override
  State<RecordButtonPress> createState() => _RecordButtonPressState();
}

class _RecordButtonPressState extends State<RecordButtonPress>
    with TickerProviderStateMixin {
  // アイコンの比率（タイルに対して輪の外径 0.695・線幅 0.035・黒丸 0.48）を外径基準に直した値
  static const _ringWidthRatio = 0.05;
  static const _dotDiameterRatio = 0.69;

  // 押したときに黒丸が縮む大きさ
  static const _pressedDotScale = 0.86;

  // 進み具合が更新されたとき、輪を次の長さまで伸ばすのにかける時間（問い合わせの間隔と同じ1秒）
  static const _ringGrowDuration = Duration(seconds: 1);

  late final AnimationController _pressController;
  late final Animation<double> _dotScale;

  // 描いている輪の長さ（0.0〜1.0）。進み具合の更新のたびに、ここから次の値までなめらかに伸ばす
  late final AnimationController _ringController;

  @override
  void initState() {
    super.initState();

    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // ---------------------------------
    // 押される流れ: 少し待つ → キュッと沈む → 弾むように戻る
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
    ]).animate(_pressController);

    if (widget.playsPress) {
      _pressController.forward();
    } else {
      _pressController.value = 1.0;
    }

    // 最初から進み具合が分かっていれば、0 からその長さまで伸ばす
    _ringController = AnimationController(
      vsync: this,
      duration: _ringGrowDuration,
    );
    _growRingTo(widget.ringProgress);
  }

  @override
  void didUpdateWidget(covariant RecordButtonPress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ringProgress == oldWidget.ringProgress) return;

    // 一周の輪から進み具合の表示に切り替わるときは、0 から伸ばし始める（一周から縮んで見えないようにする）
    if (oldWidget.ringProgress == null) _ringController.value = 0;
    _growRingTo(widget.ringProgress);
  }

  void _growRingTo(double? progress) {
    if (progress == null) return;
    _ringController.animateTo(
      progress.clamp(0.0, 1.0),
      duration: _ringGrowDuration,
      curve: Curves.linear,
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  // ---------------------------------
  // ビルド
  // ---------------------------------
  @override
  Widget build(BuildContext context) {
    final dotDiameter = widget.size * _dotDiameterRatio;
    final showsProgress = widget.ringProgress != null;

    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 外側の輪（進み具合を出すときは、その割合だけ伸びた弧）
          AnimatedBuilder(
            animation: _ringController,
            builder: (context, child) {
              return CustomPaint(
                size: Size.square(widget.size),
                painter: _RingPainter(
                  sweepFraction: showsProgress ? _ringController.value : 1.0,
                  strokeWidth: widget.size * _ringWidthRatio,
                  color: AppColors.onSurface,
                ),
              );
            },
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

// ---------------------------------
// 外側の輪を、12時の位置から時計回りに sweepFraction の割合だけ描く（1.0 で一周）
// 線は外径の内側に収める（起動画面の画像やアプリアイコンと同じ大きさにそろえるため）
// ---------------------------------
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.sweepFraction,
    required this.strokeWidth,
    required this.color,
  });

  final double sweepFraction;
  final double strokeWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (sweepFraction <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final center = size.center(Offset.zero);
    final radius = (size.width - strokeWidth) / 2;

    // 一周のときは円で描く（弧の継ぎ目を出さない）
    if (sweepFraction >= 1) {
      canvas.drawCircle(center, radius, paint);
      return;
    }

    // 伸びている途中は、線の端を丸くする
    paint.strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * sweepFraction,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) {
    return oldDelegate.sweepFraction != sweepFraction ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.color != color;
  }
}
