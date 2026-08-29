import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_text_styles.dart';

// ---------------------------------
// 文言定数
// ---------------------------------
const _title = 'ほかのアプリを使っていても録音しますか？';
const _message =
    'ほかのアプリを使っている間や画面を消している間も、マイクで音声を録り続けます。\n\n'
    '録音した音声と文字起こしはこの端末の中だけに保存され、外部に送信されることはありません。';
// Android だけ挟む一文（許可済みのとき: 録音中は常駐通知が出続けること）
const _notificationNote = '録音中は、録音していることを通知でお知らせし続けます。';
// Android だけ挟む一文（許可がまだのとき: 許可が条件であることと、「有効にする」が設定を開くことの予告）
const _notificationRequiredNote =
    'ほかのアプリを使っている時にも録音していることをお知らせし続けるため、通知の許可が必要です。'
    '「有効にする」を押すと端末の設定が開くので、momeo の通知を許可してください。';
const _closingNote = 'この設定はいつでも解除できます。';
const _cancelLabel = 'キャンセル';
const _confirmLabel = '有効にする';

// ---------------------------------
// クラス本体
// ---------------------------------
class BackgroundRecordingDisclosureDialog extends StatefulWidget {
  const BackgroundRecordingDisclosureDialog({super.key});

  // ---------------------------------
  // ダイアログを表示する
  // ---------------------------------
  static Future<bool> show(BuildContext context) async {
    final isConfirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // 外側のタップで閉じさせない
      builder: (dialogContext) => const BackgroundRecordingDisclosureDialog(),
    );
    // 同意が得られたか
    return isConfirmed == true;
  }

  @override
  State<BackgroundRecordingDisclosureDialog> createState() =>
      _BackgroundRecordingDisclosureDialogState();
}

// ---------------------------------
// 状態
// ---------------------------------
class _BackgroundRecordingDisclosureDialogState
    extends State<BackgroundRecordingDisclosureDialog>
    with WidgetsBindingObserver {

  // ---------------------------------
  // Android のみ: 通知の許可が取れているか
  // ---------------------------------
  bool _isNotificationGranted = !Platform.isAndroid;

  // ---------------------------------
  // 「有効にする」から端末の設定へ移動したか
  // ---------------------------------
  bool _hasOpenedSettingsFromConfirm = false;

  // ---------------------------------
  // 表示と同時に、今の許可状態を確認する
  // ---------------------------------
  @override
  void initState() {
    super.initState();
    // --- アプリ復帰の検知を登録する
    WidgetsBinding.instance.addObserver(this);
    // --- 通知の許可を確認
    unawaited(_refreshNotificationGranted());
  }

  // ---------------------------------
  // 後片付け
  // ---------------------------------
  @override
  void dispose() {
    // --- アプリ復帰の検知を解除する
    WidgetsBinding.instance.removeObserver(this);
    // --- 後片付け
    super.dispose();
  }

  // ---------------------------------
  // アプリがフォアグラウンドへ復帰した時
  // ---------------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // --- アプリがフォアグラウンド復帰時以外は何もしない
    if (state != AppLifecycleState.resumed) return; 

    // ---- 以下、フォアグラウンド復帰時の処理 ----

    // --- 通知の許可状態を確認
    unawaited(_refreshNotificationGranted());
  }

  // ---------------------------------
  // Android のみ: 通知の許可を確認
  // ---------------------------------
  Future<void> _refreshNotificationGranted() async {
    // --- Android でなければ何もしない
    if (!Platform.isAndroid) return;
    // --- 通知の許可が取れているか
    final isGranted = await Permission.notification.status.isGranted;
    // マウントされていない場合は何もしない
    if (!mounted) return;
    // --- 「有効にする」を選択し、端末の設定へ行き許可したら
    if (isGranted && _hasOpenedSettingsFromConfirm) {
      // --- ダイヤログを閉じる
      Navigator.of(context).pop(true);
      return;
    }
    // --- 通知の許可状態を更新
    setState(() => _isNotificationGranted = isGranted);
  }

  // ---------------------------------
  // 「有効にする」を押した時
  // ---------------------------------
  void _onConfirmPressed() {
    // --- 通知の許可が取れていれば
    if (_isNotificationGranted) {
      // --- ダイヤログを閉じる
      Navigator.of(context).pop(true);
      return;
    }
    // --- 端末の設定へ移動したことをフラグに記録
    _hasOpenedSettingsFromConfirm = true;
    // --- 端末の設定へ移動
    openAppSettings();
  }

  // ---------------------------------
  // 組み立て
  // ---------------------------------
  @override
  Widget build(BuildContext context) {

    // ---------------------------------
    // ダイアログの文字の大きさ
    // ---------------------------------
    const dialogFontSize = 15.0;

    // ---------------------------------
    // 本文を組み立てる（Android だけ、通知についての一文を挟む）
    // ---------------------------------
    final message = [
      _message,
      if (Platform.isAndroid)
        // --- 許可済みなら常駐通知が出ることだけ、まだなら許可が条件であることを伝える
        _isNotificationGranted ? _notificationNote : _notificationRequiredNote,
      _closingNote,
    ].join('\n\n');

    // ---------------------------------
    // ダイアログ
    // ---------------------------------
    return AlertDialog(
      title: Text(
        _title,
        style: AppTextStyles.button.copyWith(color: AppColors.onSurface),
      ),
      content: Text(
        message,
        style: AppTextStyles.caption.copyWith(
          fontSize: dialogFontSize,
          color: AppColors.onSurface,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            _cancelLabel,
            style: AppTextStyles.caption.copyWith(
              fontSize: dialogFontSize,
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          onPressed: _onConfirmPressed,
          child: Text(
            _confirmLabel,
            style: AppTextStyles.caption.copyWith(
              fontSize: dialogFontSize,
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
