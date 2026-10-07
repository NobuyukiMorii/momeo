import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:momeo/foundation/app_colors.dart';

final _dateFormat = DateFormat('yyyy.MM.dd');

// 日付の書体（日記らしい筆記体。pubspec.yaml で同梱）
const String _fontFamily = 'Dancing Script';

// 日付の文字サイズ
const double _fontSize = 48;

// 数字の高さ（文字サイズに対する比。Dancing Script の数字は 0.72）
const double _digitHeightRatio = 0.72;

// ---------------------------------
// スクロールつまみの位置にあるメモの日付を、背景に大きく描く
// ---------------------------------
// 置いた高さに数字の上端をそろえる。左右は本文の表示領域の中央
class ListeningMemoDateBackdrop extends StatelessWidget {
  const ListeningMemoDateBackdrop({super.key, required this.dateTime});

  final DateTime dateTime;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(
      TextStyle(
        fontFamily: _fontFamily,
        fontSize: _fontSize,
        color: AppColors.onSurfaceFaint,
      ),
    );
    final text = _dateFormat.format(dateTime);

    // 文字の枠の上端から数字の上端までの余白（行の上の余白 + 数字より高い部分）を測り、その分だけ上へずらす
    final textScaler = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
    )..layout();
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    final digitHeight = textScaler.scale(style.fontSize!) * _digitHeightRatio;
    painter.dispose();

    return IgnorePointer(
      child: Padding(
        // 本文の左右余白（左12、右は丸と縦線の領域を含めて34）にそろえる
        padding: const EdgeInsets.only(left: 12, right: 34),
        // 画面が狭いときや文字サイズの設定が大きいときも、はみ出さずに縮める（ずらす量も一緒に縮む）
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: Transform.translate(
            offset: Offset(0, -(baseline - digitHeight)),
            child: Text(text, textAlign: TextAlign.center, style: style),
          ),
        ),
      ),
    );
  }
}
