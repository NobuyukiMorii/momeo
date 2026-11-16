import 'dart:async';

import 'package:flutter/material.dart';
import 'package:momeo/widgets/record_button_press.dart';

// アプリ名（権限フローと準備ゲートの待ち画面で使う）
const splashAppName = 'momeo';

// 録音ボタンを出しておく時間
const _buttonDisplayDuration = Duration(milliseconds: 1500);

// ---------------------------------
// SplashPage — 起動時に毎回表示されるスプラッシュ画面
// 録音ボタンが押される演出だけを出して次のフローへ進む
// ---------------------------------
class SplashPage extends StatefulWidget {
  const SplashPage({super.key, this.onFinished});

  // 演出が終わった時に呼ばれるコールバック
  final VoidCallback? onFinished;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  Timer? _finishTimer;

  @override
  void initState() {
    super.initState();
    _finishTimer = Timer(_buttonDisplayDuration, () {
      widget.onFinished?.call();
    });
  }

  @override
  void dispose() {
    _finishTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // OS の起動画面と同じ大きさ・位置の録音ボタンを、フェードさせずに最初から出す
    return const Scaffold(
      body: Center(child: RecordButtonPress()),
    );
  }
}
