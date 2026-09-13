import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_radius.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/models/recording_scope.dart';
import 'package:momeo/providers/settings_providers.dart';
import 'package:momeo/widgets/background_recording_disclosure_dialog.dart';
import 'package:momeo/widgets/dot.dart';
import 'package:permission_handler/permission_handler.dart';

// ============================================================
// いつ録音するかを選ぶカード2枚
// ============================================================

// ---------------------------------
// 定数: 見た目
// ---------------------------------

// ドットの直径（選んでいる選択肢だけ少し大きくする）
const _optionDotSize = 8.0;
const _optionSelectedDotSize = 12.0;

// 枠線の太さ（選んでいる選択肢だけ太くする）
const _normalBorderWidth = 1.5;
const _selectedBorderWidth = 3.0;

// ---------------------------------
// クラス本体
// ---------------------------------
class RecordingOptionCards extends ConsumerStatefulWidget {
  const RecordingOptionCards({super.key});

  @override
  ConsumerState<RecordingOptionCards> createState() =>
      _RecordingOptionCardsState();
}

class _RecordingOptionCardsState extends ConsumerState<RecordingOptionCards> {
  // ---------------------------------
  // 選んだ範囲を設定として保存する
  // ---------------------------------
  Future<void> _selectScope(RecordingScope scope) async {
    final isEnabled = scope.enablesBackgroundRecording;
    final backgroundRecording = ref.read(backgroundRecordingProvider).value;

    // --- 初めて有効にするときは、開示ダイアログを出す
    var shouldShowDisclosureDialog =
        isEnabled && (backgroundRecording?.needsConfirmation ?? true);
    // --- 2回目以降の Android では
    if (isEnabled && !shouldShowDisclosureDialog && Platform.isAndroid) {
      // --- 通知の許可が無いときも出す
      shouldShowDisclosureDialog =
          !await Permission.notification.status.isGranted;
    }
    // --- マウントされていない場合は何もしない
    if (!mounted) return;
    // --- 開示ダイアログを出すなら
    if (shouldShowDisclosureDialog) {
      // --- 開示ダイアログを出して、同意されたかを受け取る
      final isConfirmed = await BackgroundRecordingDisclosureDialog.show(
        context,
      );
      // --- 同意が得られなければ何もしない
      if (!isConfirmed) return;
      // --- ダイアログを開いている間に画面が消えていたら何もしない
      if (!mounted) return;
    }
    // --- 設定を保存
    await ref.read(backgroundRecordingProvider.notifier).setEnabled(isEnabled);
  }

  // ---------------------------------
  // 選択肢のドット
  // ---------------------------------
  Widget _buildOptionDot({required Color dotColor, required bool isSelected}) {
    // 大きさが変わっても下の文言がずれないよう、どちらも大きいほうの箱に入れる
    return SizedBox(
      width: _optionSelectedDotSize,
      height: _optionSelectedDotSize,
      child: Center(
        child: Dot(
          color: dotColor,
          size: isSelected ? _optionSelectedDotSize : _optionDotSize,
          isBlinking: false,
        ),
      ),
    );
  }

  // ---------------------------------
  // 選択肢カード1枚
  // ---------------------------------
  Widget _buildCard(RecordingScope scope, {required bool isSelected}) {
    final borderWidth = isSelected ? _selectedBorderWidth : _normalBorderWidth;

    // カードの内側の余白（枠線が太った分だけ削り、中身の位置を保つ）
    final contentPadding = AppSpacing.l - (borderWidth - _normalBorderWidth);

    return GestureDetector(
      onTap: () => _selectScope(scope),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(contentPadding),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.l),
          border: Border.all(color: AppColors.onSurface, width: borderWidth),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- 状態の色を示すドット（選んでいる選択肢は少し大きい）
            _buildOptionDot(dotColor: scope.dotColor, isSelected: isSelected),
            const SizedBox(height: AppSpacing.xs),
            // --- タイトル
            Text(
              scope.title,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            // --- 説明文
            Text(
              scope.description,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------
  // 組み立て
  // ---------------------------------
  @override
  Widget build(BuildContext context) {
    final backgroundRecording = ref.watch(backgroundRecordingProvider).value;
    final selectedScope = RecordingScope.of(
      isBackgroundRecordingEnabled: backgroundRecording?.isEnabled ?? false,
    );

    // 高さは中身なりに決まる。2枚の背丈は、中身の多いほうに合わせてそろえる
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- このアプリを使っている間だけ
          Expanded(
            child: _buildCard(
              RecordingScope.foregroundOnly,
              isSelected: selectedScope == RecordingScope.foregroundOnly,
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          // --- ほかのアプリを使っていても
          Expanded(
            child: _buildCard(
              RecordingScope.background,
              isSelected: selectedScope == RecordingScope.background,
            ),
          ),
        ],
      ),
    );
  }
}
