import 'package:permission_handler/permission_handler.dart';

// 権限画面の表示状態
// null を返す場合は「許可済み・画面表示不要」を意味する
enum PermissionScreenState { request, settings, unavailable }

// ---------------------------------
// PermissionController — 権限操作のロジック層
// permission_handler をラップし、仕様の3状態（request/settings/unavailable）に変換する
// ---------------------------------
class PermissionController {
  // ---------------------------------
  // 現在の権限状態を確認する
  // 許可済みの場合は null を返す（画面表示不要）
  // ---------------------------------
  Future<PermissionScreenState?> check(Permission permission) async {
    final status = await permission.status;
    return _toScreenState(status);
  }

  // ---------------------------------
  // OSの権限ダイアログを表示してリクエストする
  // 許可された場合は true を返す
  // ---------------------------------
  Future<bool> request(Permission permission) async {
    final status = await permission.request();
    return status.isGranted;
  }

  // ---------------------------------
  // OSの設定アプリを開く（permanentlyDenied 時に使用）
  // ---------------------------------
  Future<void> openSettings() => openAppSettings();

  // ---------------------------------
  // PermissionStatus → 仕様の PermissionScreenState に変換
  // ---------------------------------
  PermissionScreenState? _toScreenState(PermissionStatus status) {
    // ---------------------------------
    // 許可済みの場合
    // ---------------------------------
    if (status.isGranted) return null;

    // ---------------------------------
    // 拒否されている場合
    // ---------------------------------
    if (status.isDenied) return PermissionScreenState.request;

    // ---------------------------------
    // 永久に拒否されている場合
    // ---------------------------------
    if (status.isPermanentlyDenied) return PermissionScreenState.settings;

    // ---------------------------------
    // そもそも許可できない制約がある場合
    // ---------------------------------
    return PermissionScreenState.unavailable;
  }
}
