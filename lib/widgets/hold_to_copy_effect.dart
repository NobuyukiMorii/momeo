import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_text_styles.dart';

// ============================================================
// HoldToCopyEffect — 長押しコピーの「塗りつぶし」演出
//
//   child（カード本体）に長押しジェスチャーを付け、押さえている間、
//   カード背景を右から左へ枠線と同じ黒で塗りつぶしていく。
//   左端まで塗りつぶし切るとコピー確定として onCopied を通知し、
//   黒背景の中央に白文字で COPY を表示して、少し置いて通常表示へ戻る。
//   途中で指が離れたら塗りつぶしは右へ引いて戻る（キャンセル）。
//   onCopied が null のときはジェスチャーごと無効になる。
// ============================================================

// ---------------------------------
// 調整用パラメータ
// ---------------------------------

// 長押し成立までの時間（標準の500msより短くして反応を早くする）
const _holdDelay = Duration(milliseconds: 300);

// 塗りつぶし切るまでの時間（＝コピー確定までの押し続け時間）
const _fillDuration = Duration(milliseconds: 150);

// キャンセル時に塗りつぶしが右へ引いて戻る時間
const _drainDuration = Duration(milliseconds: 200);

// コピー確定後、COPY 表示を見せておく時間
const _copyHoldDuration = Duration(milliseconds: 600);

// COPY 表示後、通常表示へフェードで戻る時間
const _fadeOutDuration = Duration(milliseconds: 250);

// COPY 表示の文字スタイル
final _copyLabelStyle = AppTextStyles.button.copyWith(
  color: AppColors.surface,
  letterSpacing: 2,
);

// コピー確定後の「COPY を見せて通常表示へ戻す」シーケンスの段階
enum _FinishPhase { none, showCopy, fadeOut }

class HoldToCopyEffect extends StatefulWidget {
  const HoldToCopyEffect({
    super.key,
    required this.borderRadius,
    required this.child,
    this.onCopied,
  });

  // 塗りつぶしを child の角丸に合わせて切り抜くための半径
  final double borderRadius;

  final Widget child;

  // 塗りつぶし切ったときの通知（＝コピー実行の合図）
  final VoidCallback? onCopied;

  @override
  State<HoldToCopyEffect> createState() => _HoldToCopyEffectState();
}

class _HoldToCopyEffectState extends State<HoldToCopyEffect>
    with SingleTickerProviderStateMixin {
  // 塗りつぶしの進行（0 = なし、1 = 左端まで到達）
  late final AnimationController _fill;

  _FinishPhase _finishPhase = _FinishPhase.none;

  Timer? _timer;

  // コピー確定後の見せて戻すシーケンスに入っているか
  bool get _finishing => _finishPhase != _FinishPhase.none;

  @override
  void initState() {
    super.initState();
    _fill = AnimationController(
      vsync: this,
      duration: _fillDuration,
      reverseDuration: _drainDuration,
    );
    _fill.addStatusListener(_onFillStatus);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fill.dispose();
    super.dispose();
  }

  // ---------------------------------
  // コピー確定後のシーケンス
  //   塗りつぶし完了 → COPY 表示 → フェード → 待機に戻る
  // ---------------------------------

  // 左端まで到達 → コピーの合図を出し、COPY 表示へ
  void _onFillStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    widget.onCopied?.call();
    setState(() => _finishPhase = _FinishPhase.showCopy);
    _timer = Timer(_copyHoldDuration, _startFadeOut);
  }

  // COPY を見せ終えたら通常表示へのフェードを始める
  void _startFadeOut() {
    setState(() => _finishPhase = _FinishPhase.fadeOut);
    _timer = Timer(_fadeOutDuration, _resetToIdle);
  }

  // フェードし切ったら演出を終了して待機に戻す
  void _resetToIdle() {
    setState(() {
      _finishPhase = _FinishPhase.none;
      _fill.value = 0;
    });
  }

  // ---------------------------------
  // 長押しジェスチャー
  // ---------------------------------

  void _handlePressStart(LongPressStartDetails details) {
    if (_finishing) return;
    _fill.forward(from: 0);
  }

  // 指が離れた（キャンセル含む）。塗りつぶし切る前なら右へ引いて戻す
  void _handlePressRelease() {
    if (_finishing) return;
    _fill.reverse();
  }

  @override
  Widget build(BuildContext context) {
    // コピー対象でないカードは演出もジェスチャーも持たない
    if (widget.onCopied == null) return widget.child;

    return RawGestureDetector(
      // 標準の GestureDetector では長押し成立時間を変えられないため、
      // LongPressGestureRecognizer を直接組み立てる
      gestures: {
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(duration: _holdDelay),
              (instance) {
                instance.onLongPressStart = _handlePressStart;
                instance.onLongPressEnd = (_) => _handlePressRelease();
                instance.onLongPressCancel = _handlePressRelease;
              },
            ),
      },
      child: Stack(
        children: [
          widget.child,
          // 塗りつぶしと COPY 表示のオーバーレイ（待機中は何も描かない）
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _fill,
                builder: (context, _) {
                  if (_fill.value == 0 && !_finishing) {
                    return const SizedBox.shrink();
                  }
                  return AnimatedOpacity(
                    opacity: _finishPhase == _FinishPhase.fadeOut ? 0.0 : 1.0,
                    duration: _fadeOutDuration,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(widget.borderRadius),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 右端から左へ広がる黒い塗りつぶし
                          Align(
                            alignment: Alignment.centerRight,
                            child: FractionallySizedBox(
                              widthFactor: _fill.value,
                              heightFactor: 1,
                              child: const ColoredBox(
                                color: AppColors.onSurface,
                              ),
                            ),
                          ),
                          if (_finishing)
                            Center(child: Text('COPY', style: _copyLabelStyle)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
