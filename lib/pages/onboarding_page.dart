import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/widgets/animated_text_sequence.dart';
import 'package:momeo/widgets/intro_setting_layout.dart';

// オンボーディングで順番に表示するテキスト
const _onboardingTexts = [
  'momeo',
  'Open. Speak. Saved.',
  'Auto-start',
  'Auto-stop',
];

// ---------------------------------
// OnboardingPage — 初回起動時に1回だけ表示されるオンボーディング画面
// ---------------------------------
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({
    super.key,
    this.onFinished,
  });

  // 全テキストの表示が終わった時に呼ばれるコールバック
  final VoidCallback? onFinished;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IntroSettingLayout(
        title: DefaultTextStyle(
          style: AppTextStyles.headline.copyWith(
            color: AppColors.onSurface,
          ),
          child: AnimatedTextSequence(
            texts: _onboardingTexts,
            onFinished: onFinished,
          ),
        ),
      ),
    );
  }
}
