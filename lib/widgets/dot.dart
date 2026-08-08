import 'dart:async';

import 'package:flutter/material.dart';

// 点いている時間と消えている時間の既定値
const _defaultBlinkInterval = Duration(milliseconds: 800);

// ドットの直径の既定値
const _defaultDotSize = 8.0;

// ---------------------------------
// ドット
// ---------------------------------
class Dot extends StatefulWidget {
  const Dot({
    super.key,
    required this.color,
    this.size = _defaultDotSize,
    this.blinkInterval = _defaultBlinkInterval,
  });

  // ドットの色
  final Color color;

  // ドットの直径
  final double size;

  // 点いている時間と消えている時間
  final Duration blinkInterval;

  @override
  State<Dot> createState() => _DotState();
}

// ---------------------------------
// ドットの状態
// ---------------------------------
class _DotState extends State<Dot> {
  
  // ---------------------------------
  // 今出しているか（点滅で入れ替わる）
  // ---------------------------------
  bool _isVisible = true;

  // 表示を切り替えるタイマー
  Timer? _blinkTimer;

  // ---------------------------------
  // 点滅を始める
  // ---------------------------------
  @override
  void initState() {
    // --- 親の初期化を先に済ませる
    super.initState();
    // --- 点滅を始める
    _startBlinking();
  }

  // ---------------------------------
  // 間隔が変わったら、新しい間隔で点滅し直す
  // ---------------------------------
  @override
  void didUpdateWidget(Dot oldWidget) {
    // --- 親の処理を先に済ませる
    super.didUpdateWidget(oldWidget);
    // --- 間隔が同じなら、今のタイマーをそのまま使う
    if (widget.blinkInterval == oldWidget.blinkInterval) return;
    // --- 間隔が変わったので、タイマーを張り替える
    _startBlinking();
  }

  // ---------------------------------
  // 一定の間隔で表示を反転させるタイマーを張り直す
  // ---------------------------------
  void _startBlinking() {
    // --- 前のタイマーが残っていれば止める
    _blinkTimer?.cancel();
    // --- 新しい間隔で掛け直す
    _blinkTimer = Timer.periodic(
      widget.blinkInterval,
      (_) => setState(() => _isVisible = !_isVisible),
    );
  }

  // ---------------------------------
  // 後片付け
  // ---------------------------------
  @override
  void dispose() {
    // --- 点滅を止める
    _blinkTimer?.cancel();
    // --- 親の後片付けを最後に行う
    super.dispose();
  }

  // ---------------------------------
  // 組み立て
  // ---------------------------------
  @override
  Widget build(BuildContext context) {
    return Opacity(
      // 消えている間も場所を取り続け、周りの表示が動かないようにする
      opacity: _isVisible ? 1.0 : 0.0,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
