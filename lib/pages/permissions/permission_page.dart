import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:momeo/pages/permissions/permission_controller.dart';
import 'package:momeo/widgets/intro_setting_layout.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_text_styles.dart';

// ---------------------------------
// 権限 × 状態の表示データ（タイトルとボタンラベルの対応表）
// ---------------------------------
final _content = {
  Permission.microphone: {
    PermissionScreenState.request: (
      title: 'Allow Microphone Access',
      button: 'allow' as String?,
    ),
    PermissionScreenState.settings: (
      title: 'Allow Microphone Access',
      button: 'Open Settings' as String?,
    ),
    PermissionScreenState.unavailable: (
      title: 'Allow Microphone Access Not Available',
      button: null as String?,
    ),
  },
  Permission.speech: {
    PermissionScreenState.request: (
      title: 'Allow Speech Recognition',
      button: 'allow' as String?,
    ),
    PermissionScreenState.settings: (
      title: 'Allow Speech Recognition',
      button: 'Open Settings' as String?,
    ),
    PermissionScreenState.unavailable: (
      title: 'Speech Recognition Not Available',
      button: null as String?,
    ),
  },
};

// ---------------------------------
// PermissionPage — 権限リクエスト画面（描画層・Stateless）
// (permission, state, step) を受け取り IntroSettingLayout で描画する
// ---------------------------------
class PermissionPage extends StatelessWidget {
  const PermissionPage({
    super.key,
    required this.permission,
    required this.state,
    this.step,
    this.onAction,
  });

  final Permission permission;
  final PermissionScreenState state;
  final String? step;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final content = _content[permission]![state]!;
    return Scaffold(
      body: IntroSettingLayout(
        step: step,
        title: DefaultTextStyle(
          style: AppTextStyles.headline.copyWith(color: AppColors.onSurface),
          child: Text(content.title),
        ),
        actionLabel: content.button,
        onAction: onAction,
      ),
    );
  }
}
