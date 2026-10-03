import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:momeo/database/app_database.dart';
import 'package:momeo/foundation/app_colors.dart';

// ネイティブ側（NativeMemoListFactory）の登録名とそろえる、View の種類名
const _viewType = 'jp.momeo/native_memo_list';

// ネイティブ側へ呼び出すメソッド
const _updateMethod = 'update';

// 本文の文字サイズ（端末の文字サイズの設定で拡大する前の値）
const _bodyFontSize = 18.0;

// ---------------------------------
// メモ一覧を1つの文書にしてネイティブ側へ渡し、表示とスクロールは OS の部品に任せる
// ---------------------------------
class NativeMemoList extends StatefulWidget {
  const NativeMemoList({super.key, required this.memos});

  // 確定済みメモ一覧（新しい順）
  final List<VoiceMemo> memos;

  @override
  State<NativeMemoList> createState() => _NativeMemoListState();
}

class _NativeMemoListState extends State<NativeMemoList> {
  // ネイティブ View とのやり取りの窓口（View ができるまでは null）
  MethodChannel? _channel;
  // ネイティブ側へ渡す文書（ブロックと表示の設定）
  Map<String, Object?> _document = const {};
  // 最後に送った文書を文字列にしたもの（中身が変わっていなければ送り直さない）
  String? _lastSignature;
  // 描画後に文書を送る予約が入っているか
  bool _updatePending = false;

  // ---------------------------------
  // ネイティブ View ができたとき
  // ---------------------------------
  void _onPlatformViewCreated(int viewId) {
    _channel = MethodChannel('$_viewType/$viewId');
    // 作っている間に変わった文書を渡し直す
    _channel!.invokeMethod<void>(_updateMethod, _document);
  }

  // ---------------------------------
  // ネイティブ側へ渡す文書（ブロックは古い順）
  // ---------------------------------
  Map<String, Object?> _buildDocument() {
    final blocks = [
      for (final memo in widget.memos.reversed)
        {'id': memo.id, 'text': memo.content},
    ];
    return {
      'blocks': blocks,
      'fontSize': MediaQuery.textScalerOf(context).scale(_bodyFontSize),
      'textColor': AppColors.onSurface.toARGB32(),
    };
  }

  // ---------------------------------
  // 文書の中身が変わったときだけ、描画を終えてからまとめて1回送る
  // ---------------------------------
  void _sendDocumentIfChanged() {
    final signature = jsonEncode(_document);
    if (signature == _lastSignature) return;
    _lastSignature = signature;
    if (_updatePending) return;
    _updatePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePending = false;
      if (mounted) _channel?.invokeMethod<void>(_updateMethod, _document);
    });
  }

  // ---------------------------------
  // ネイティブ View
  // ---------------------------------
  Widget _buildPlatformView() {
    // 一覧の上の操作（スクロールなど）は、Flutter 側で取り合わずにすべて渡す
    final gestures = <Factory<OneSequenceGestureRecognizer>>{
      Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
    };
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: _viewType,
        creationParams: _document,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: gestures,
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    }
    // OS の文字選択のメニュー・つまみを正しく出せるよう、実際の View 階層に配置する
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        gestureRecognizers: gestures,
      ),
      onCreatePlatformView: (params) {
        final controller = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: _document,
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        );
        controller.addOnPlatformViewCreatedListener(
          params.onPlatformViewCreated,
        );
        controller.addOnPlatformViewCreatedListener(_onPlatformViewCreated);
        controller.create();
        return controller;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _document = _buildDocument();
    _sendDocumentIfChanged();
    return _buildPlatformView();
  }
}
