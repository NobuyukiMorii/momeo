import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:momeo/constants/preferences_keys.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/widgets/animated_text_sequence.dart';
import 'package:momeo/widgets/intro_setting_layout.dart';

// 初回起動時に表示するフルシーケンス
const _splashFullTexts = [
  'momeo',
  'Open. Speak. Saved.',
  'Auto-start',
  'Auto-stop',
];

// 2回目以降に表示する短縮シーケンス
const _splashShortTexts = ['momeo'];

// ---------------------------------
// SplashPage — 起動時に毎回表示されるスプラッシュ画面
// 初回起動時: フルシーケンスを表示
// 2回目以降: 'momeo' だけ表示して即座に次のフローへ進む
// ---------------------------------
class SplashPage extends StatefulWidget {
  const SplashPage({super.key, this.onFinished});

  // 全テキストの表示が終わった時に呼ばれるコールバック
  final VoidCallback? onFinished;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  // null の間は SharedPreferences の読み取り中
  List<String>? _texts;

  // ---------------------------------
  // 初期化: SharedPreferences を読んで表示するテキストを決める
  // ---------------------------------
  @override
  void initState() {
    super.initState();
    _loadTexts();
  }

  Future<void> _loadTexts() async {

    // ---------------------------------
    // SharedPreferences を読んで初回起動かどうかを判断
    // ---------------------------------
    final prefs = await SharedPreferences.getInstance();
    final isFirstLaunch = prefs.getBool(PreferencesKeys.isFirstLaunch) ?? true;

    // ---------------------------------
    // マウントされていない場合は何もしない
    // ---------------------------------
    if (!mounted) return;

    // ---------------------------------
    // テキストを設定
    // ---------------------------------
    setState(() {
      _texts = isFirstLaunch ? _splashFullTexts : _splashShortTexts;
    });
  }

  // ---------------------------------
  // シーケンス完了時: 初回フラグを書き込んで親へ通知
  // ---------------------------------
  Future<void> _onSequenceFinished() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PreferencesKeys.isFirstLaunch, false);

    widget.onFinished?.call();
  }

  // ---------------------------------
  // ビルド
  // ---------------------------------
  @override
  Widget build(BuildContext context) {
    // テキストが決まるまでは背景色のみ表示
    if (_texts == null) {
      return const Scaffold();
    }

    return Scaffold(
      body: IntroSettingLayout(
        title: DefaultTextStyle(
          style: AppTextStyles.headline.copyWith(
            color: AppColors.onSurface,
          ),
          child: AnimatedTextSequence(
            texts: _texts!,
            onFinished: _onSequenceFinished,
          ),
        ),
      ),
    );
  }
}
