import 'dart:async';

import 'package:flutter/material.dart';

// ---------------------------------
// ラベル末尾のドットで処理中を示すテキスト
// ---------------------------------
class ActivityDotsText extends StatefulWidget {
  const ActivityDotsText(
    this.label, {
    super.key,
    this.interval = const Duration(milliseconds: 500),
    this.maxDotCount = 3,
  });

  // ドットの前に表示する固定ラベル
  final String label;

  // ドットが1段階進むまでの間隔
  final Duration interval;

  // ドットの最大数（0〜この数を巡回する）
  final int maxDotCount;

  @override
  State<ActivityDotsText> createState() => _ActivityDotsTextState();
}

class _ActivityDotsTextState extends State<ActivityDotsText> {
  late final Timer _timer;

  // 現在表示中のドット数（0〜maxDotCount を巡回）
  int _dotCount = 0;

  @override
  void initState() {
    super.initState();

    _timer = Timer.periodic(widget.interval, (_) {
      setState(() {
        _dotCount = (_dotCount + 1) % (widget.maxDotCount + 1);
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 左揃えで使う想定（中央揃えの場所に置くと、ドットの増減でラベル位置が揺れる）
    return Text('${widget.label} ${'.' * _dotCount}');
  }
}
