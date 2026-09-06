import 'dart:async';

import 'package:flutter/material.dart';

// ============================================================
// 押している間だけ少し縮む入れ物
//
//   押した手応えを見た目で返すためのもの。指を離してもすぐには戻さず、
//   短いタップでも反応が見える長さだけ縮んだままにする。加えて、続けざまの
//   タップは間引いて、同じ操作が二重に走らないようにする。
// ============================================================

// 押している間の縮み具合
const _pressedScale = 0.99;

// 縮むときは速く、戻るときはゆっくり（戻りが速いと押した手応えが目に残らない）
const _pressInDuration = Duration(milliseconds: 60);
const _pressOutDuration = Duration(milliseconds: 180);

// 縮んだ見た目を保つ最低の時間（速いタップでも反応が見えるようにする）
const _minPressedDuration = Duration(milliseconds: 120);

// 次のタップを受け付けるまでの間隔（続けざまのタップを間引く）
const _minTapInterval = Duration(milliseconds: 120);

class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;

  // null なら押せない（縮みもしない）
  final VoidCallback? onTap;

  // 長押ししたときの通知（タップとは別の結果になる操作に使う）
  final VoidCallback? onLongPress;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  // ---------------------------------
  // 状態
  // ---------------------------------

  // 今、縮んだ見た目にしているか
  bool _isPressed = false;

  // 縮み始めた時刻（最低の表示時間を測るのに使う）
  DateTime? _pressedAt;

  // 最後に操作を通した時刻（続けざまのタップを間引くのに使う）
  DateTime? _lastHandledAt;

  // 最低の表示時間が過ぎたら元の大きさへ戻すタイマー
  Timer? _releaseTimer;

  @override
  void dispose() {
    _releaseTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------
  // 指が触れたとき（すぐ縮め始める）
  // ---------------------------------
  void _startPress() {
    if (widget.onTap == null && widget.onLongPress == null) return;
    _releaseTimer?.cancel();
    _pressedAt = DateTime.now();
    setState(() => _isPressed = true);
  }

  // ---------------------------------
  // 縮んだ見た目を終える（最低の表示時間に足りなければ、その分だけ待つ）
  // ---------------------------------
  void _endPress() {
    if (!_isPressed) return;
    final pressedFor = DateTime.now().difference(_pressedAt!);
    final remaining = _minPressedDuration - pressedFor;
    if (remaining <= Duration.zero) {
      setState(() => _isPressed = false);
      return;
    }
    _releaseTimer?.cancel();
    _releaseTimer = Timer(remaining, () {
      if (mounted) setState(() => _isPressed = false);
    });
  }

  // ---------------------------------
  // 前の操作から間が空いているか（空いていなければ間引く）
  // ---------------------------------
  bool _canHandleNow() {
    final lastHandledAt = _lastHandledAt;
    final now = DateTime.now();
    if (lastHandledAt != null &&
        now.difference(lastHandledAt) < _minTapInterval) {
      return false;
    }
    _lastHandledAt = now;
    return true;
  }

  // ---------------------------------
  // タップが成立したとき
  // ---------------------------------
  void _handleTap() {
    if (!_canHandleNow()) return;
    widget.onTap?.call();
  }

  // ---------------------------------
  // 長押しが成立したとき（縮んだ見た目はここで戻し始める）
  // ---------------------------------
  void _handleLongPress() {
    _endPress();
    if (!_canHandleNow()) return;
    widget.onLongPress?.call();
  }

  // ---------------------------------
  // 組み立て
  // ---------------------------------
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      onTapDown: (_) => _startPress(),
      onTapUp: (_) => _endPress(),
      onTapCancel: _endPress,
      onLongPress: widget.onLongPress == null ? null : _handleLongPress,
      child: AnimatedScale(
        scale: _isPressed ? _pressedScale : 1.0,
        duration: _isPressed ? _pressInDuration : _pressOutDuration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
