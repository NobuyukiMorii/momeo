import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/widgets/intro_setting_layout.dart';

// ---------------------------------
// PreparationGatePage — 文字化エンジンの準備が終わるまで受け止める待ち画面
// リスニング画面（Step 10）とは別物で、準備完了までの間だけ表示する
// このステップでは仮の固定テキスト1行のみ。文言出し分け・DL%表示は Step 12 で仕上げる
// ---------------------------------
class PreparationGatePage extends StatelessWidget {
  const PreparationGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IntroSettingLayout(
        title: Text(
          'Getting ready',
          style: AppTextStyles.headline.copyWith(
            color: AppColors.onSurface,
          ),
        ),
      ),
    );
  }
}
