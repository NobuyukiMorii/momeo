import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

// ============================================================
// TypewriterText — テキストを1文字ずつ素早く打ち出して表示する
//
//   enabled が false のときは全文を即表示する。長文でも一定時間内に
//   打ち終わるよう、1回に進める文字数の方を増やす。絵文字なども
//   見た目の1文字単位で扱う。
//
//   typeFrom を渡すと、その位置までは即表示して続きだけを打ち出す。
//   本文への書き足しで、既に読めている部分を打ち直さないために使う。
// ============================================================
class TypewriterText extends StatefulWidget {
  const TypewriterText(
    this.text, {
    super.key,
    this.enabled = true,
    this.typeFrom = 0,
    this.style,
    this.onFinished,
  });

  final String text;

  // 演出を再生するか（false なら全文を即表示）
  final bool enabled;

  // タイピングのアニメーションを始める text 上の位置
  final int typeFrom;

  final TextStyle? style;

  // 演出を使い切ったときの通知（打ち終わり時と、見せ切る前に破棄されたとき）
  final VoidCallback? onFinished;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  // タイピングの間隔と、長文でもこの時間内に収まるよう1回の文字数を増やす
  static const _tick = Duration(milliseconds: 30);
  static const _maxDuration = Duration(milliseconds: 1800);

  // テキストを見た目の1文字単位（絵文字等も1つ扱い）に分けたもの
  late List<String> _graphemes;

  // 現在表示している文字数
  late int _visibleCount;

  Timer? _timer;

  bool get _finished => _visibleCount >= _graphemes.length;

  @override
  void initState() {
    super.initState();
    _start();
  }

  // タイピングを開始する（enabled でなければ全文を即表示）
  void _start() {
    _graphemes = widget.text.characters.toList();

    // 即表示する頭の部分（範囲の外を渡されても本文に収める）
    final head = widget.text.substring(
      0,
      widget.typeFrom.clamp(0, widget.text.length),
    );

    // 見た目の1文字単位で数え直す（typeFrom はコード上の位置なので単位が違う）
    final headCount = head.characters.length;

    // 演出が無効、または打ち出すものが残っていなければ全文を即表示する
    if (!widget.enabled || headCount >= _graphemes.length) {
      _visibleCount = _graphemes.length;
      return;
    }

    _visibleCount = headCount; // 頭の部分は最初から出しておく
    final typedCount = _graphemes.length - headCount; // これから打ち出す文字数
    final maxTicks = _maxDuration.inMilliseconds ~/ _tick.inMilliseconds; // 打ち終わるまでの回数
    final charsPerTick = max(1, (typedCount / maxTicks).ceil()); // 1回に進める文字数

    _timer = Timer.periodic(_tick, (timer) {
      setState(() {
        _visibleCount = min(_visibleCount + charsPerTick, _graphemes.length);
      });
      if (_finished) {
        timer.cancel();
        widget.onFinished?.call();
      }
    });
  }

  @override
  void didUpdateWidget(TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 打ち出しに関わる値が何も変わっていなければ、今の再生をそのまま続ける
    if (oldWidget.text == widget.text &&
        oldWidget.enabled == widget.enabled &&
        oldWidget.typeFrom == widget.typeFrom) {
      return;
    }
    _timer?.cancel();
    if (widget.enabled && oldWidget.text != widget.text) {
      _start();
    } else {
      // 演出が外れた → 全文を即表示
      _graphemes = widget.text.characters.toList();
      _visibleCount = _graphemes.length;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    // 打ち終わる前に破棄された場合（画面外へのスクロール等）も使い切り扱いにする。
    // 破棄処理の最中に親の setState を呼ばないよう、通知は次のイベントループへ
    if (widget.enabled && !_finished && widget.onFinished != null) {
      scheduleMicrotask(widget.onFinished!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(_graphemes.take(_visibleCount).join(), style: widget.style);
  }
}
