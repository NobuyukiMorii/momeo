import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:momeo/pages/permissions/permission_controller.dart';
import 'package:momeo/pages/permissions/permission_page.dart';

// ---------------------------------
// PermissionFlowPage — 権限フロー制御（Stateful + WidgetsBindingObserver）
// 権限チェック → 画面表示 → 次の権限へ、の一連のフローを管理する
// ---------------------------------
class PermissionFlowPage extends StatefulWidget {
  const PermissionFlowPage({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<PermissionFlowPage> createState() => _PermissionFlowPageState();
}

class _PermissionFlowPageState extends State<PermissionFlowPage> with WidgetsBindingObserver {

  // ---------------------------------
  // 権限の確認・リクエストを担うコントローラー
  // ---------------------------------
  final _controller = PermissionController();

  // ---------------------------------
  // プラットフォームごとの確認対象権限
  // ---------------------------------
  static final _permissionsByPlatform = {
    'ios':     [Permission.microphone],
    'android': [Permission.microphone],
  };

  // ---------------------------------
  // 現在のプラットフォームで必要な権限リスト
  // ---------------------------------
  List<Permission> get _allPermissions =>
      _permissionsByPlatform[Platform.operatingSystem] ?? [Permission.microphone];

  // 今回のセッションで通過が必要な権限リスト
  List<Permission> _neededPermissions = [];

  // 現在表示中の権限インデックス
  int _currentIndex = 0;

  // 現在の画面状態（null = 初期化中）
  PermissionScreenState? _currentState;

  @override
  void initState() {
    super.initState();
    // didChangeAppLifecycleState の通知を受け取るため（登録）
    WidgetsBinding.instance.addObserver(this);
    _initFlow();
  }

  @override
  void dispose() {
    // didChangeAppLifecycleState の通知を受け取るため（解除）
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ---------------------------------
  // アプリ復帰時に現在の権限状態を再チェック
  // （設定アプリで権限を変更して戻った場合に対応）
  // ---------------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ---------------------------------
    // アプリ復帰時
    // ---------------------------------
    if (state == AppLifecycleState.resumed) {
      _recheckCurrentPermission(); // 現在の権限状態を再チェック
    }
  }

  // ---------------------------------
  // 初期化: 許可が必要な権限リストを組み立てる
  // すべて許可済みなら即座に onFinished を呼ぶ
  // ---------------------------------
  Future<void> _initFlow() async {
    // ---------------------------------
    // 許可が必要な権限リストを組み立てる
    // ---------------------------------
    final needed = <Permission>[];
    for (final permission in _allPermissions) {
      final state = await _controller.check(permission);
      if (state != null) needed.add(permission);
    }

    if (!mounted) return;

    // ---------------------------------
    // すべて許可済みなら即座に onFinished を呼ぶ
    // ---------------------------------
    if (needed.isEmpty) {
      widget.onFinished();
      return;
    }

    // ---------------------------------
    // 許可が必要な権限リストを設定する
    // ---------------------------------
    _neededPermissions = needed;

    // ---------------------------------
    // 現在の権限状態を読み込んで画面を更新する
    // ---------------------------------
    await _loadCurrentState();
  }

  // ---------------------------------
  // 現在インデックスの権限状態を読み込んで画面を更新する
  // すでに許可済みであれば次の権限へ進む
  // ---------------------------------
  Future<void> _loadCurrentState() async {
    // ---------------------------------
    // 現在の権限状態を読み込む
    // ---------------------------------
    final state = await _controller.check(_neededPermissions[_currentIndex]);
    if (!mounted) return;

    // ---------------------------------
    // 許可済みであれば次の権限へ進む
    // ---------------------------------
    if (state == null) {
      _advance();
      return;
    }

    // ---------------------------------
    // 現在の権限状態を設定して画面を更新する
    // ---------------------------------
    setState(() => _currentState = state);
  }

  // ---------------------------------
  // 現在の権限を再チェック（設定アプリから戻った時など）
  // ---------------------------------
  Future<void> _recheckCurrentPermission() async {
    if (_neededPermissions.isEmpty) return;
    await _loadCurrentState();
  }

  // ---------------------------------
  // 次の権限へ進む（全完了なら onFinished を呼ぶ）
  // ---------------------------------
  void _advance() {
    // ---------------------------------
    // 全完了なら onFinished を呼ぶ
    // ---------------------------------
    if (_currentIndex + 1 >= _neededPermissions.length) {
      widget.onFinished();
      return;
    }
    // ---------------------------------
    // 次の権限へ進む
    // ---------------------------------
    setState(() {
      _currentIndex++;
      _currentState = null;
    });
    _loadCurrentState();
  }

  // ---------------------------------
  // ボタンタップ時のアクション
  // ---------------------------------
  Future<void> _onAction() async {
    // ---------------------------------
    // 許可リクエスト
    // ---------------------------------
    if (_currentState == PermissionScreenState.request) {
      final granted = await _controller.request(_neededPermissions[_currentIndex]);
      if (!mounted) return;
      if (granted) { // 許可された場合
        _advance(); // 次の権限へ進む
      } else {
        // 拒否後に permanentlyDenied になっている可能性があるため再チェック
        await _loadCurrentState();
      }
    }
    // ---------------------------------
    // 設定アプリ移動
    // ---------------------------------
    else if (_currentState == PermissionScreenState.settings) {
      await _controller.openSettings();
      // 設定アプリへ移動: 復帰は didChangeAppLifecycleState で検知する
    }
  }

  // ---------------------------------
  // ステップ表示の文字列（1権限のみの場合は非表示）
  // ---------------------------------
  String? get _stepLabel {
    // ---------------------------------
    // 1権限のみの場合は非表示
    // ---------------------------------
    if (_neededPermissions.length <= 1) return null;

    // ---------------------------------
    // ステップ表示の文字列を返す
    // ---------------------------------
    return '${_currentIndex + 1}/${_neededPermissions.length}';
  }

  @override
  Widget build(BuildContext context) {
    // ---------------------------------
    // 初期化中は背景色のみ表示
    // ---------------------------------
    if (_currentState == null) return const Scaffold();

    // ---------------------------------
    // 権限画面を表示
    // ---------------------------------
    return PermissionPage(
      permission: _neededPermissions[_currentIndex],
      state: _currentState!,
      step: _stepLabel,
      onAction: () => _onAction(),
    );
  }
}
