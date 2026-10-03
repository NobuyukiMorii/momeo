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
const _clearSelectionMethod = 'clearSelection';

// ネイティブ側から届くメソッド
const _toggleBlockMethod = 'toggleBlock';
const _thumbMethod = 'thumb';

// 本文の文字サイズ（端末の文字サイズの設定で拡大する前の値）
const _bodyFontSize = 18.0;

// 文字選択をブロックをまたいでコピーしたときの、ブロック同士の区切り
const _copySeparator = '\n\n';

// スクロールつまみの高さ（一覧の上端から測る）と、その高さにあるメモ
// scrolling は、指やつまみの操作でスクロールしたときだけ true（新しいメモで末尾へ移るときは false）
typedef MemoListThumb = ({int memoId, double y, bool scrolling});

// ---------------------------------
// 本文の外から、OS が保持している文字選択を解除する
// ---------------------------------
class NativeMemoListController extends ChangeNotifier {
  void clearSelection() => notifyListeners();
}

// ---------------------------------
// メモ一覧を1つの文書にしてネイティブ側へ渡し、表示・スクロール・文字選択は OS の部品に任せる
// ---------------------------------
class NativeMemoList extends StatefulWidget {
  const NativeMemoList({
    super.key,
    required this.memos,
    required this.selectedIds,
    required this.controller,
    required this.onToggleSelection,
    required this.onThumbChanged,
  });

  // 確定済みメモ一覧（新しい順）
  final List<VoiceMemo> memos;
  // 丸で選ばれているメモの id
  final Set<int> selectedIds;
  final NativeMemoListController controller;
  // 丸が押されたとき
  final ValueChanged<int> onToggleSelection;
  // スクロールつまみの高さ、またはその高さにあるメモが変わったとき
  final ValueChanged<MemoListThumb> onThumbChanged;

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
  // View ができる前に、文字選択の解除を頼まれたか
  bool _clearPending = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_clearSelection);
  }

  @override
  void didUpdateWidget(NativeMemoList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_clearSelection);
      widget.controller.addListener(_clearSelection);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_clearSelection);
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  // ---------------------------------
  // 文字選択の解除（View ができる前なら、できたときに解除する）
  // ---------------------------------
  void _clearSelection() {
    if (_channel == null) {
      _clearPending = true;
    } else {
      _channel!.invokeMethod<void>(_clearSelectionMethod);
    }
  }

  // ---------------------------------
  // ネイティブ View ができたとき
  // ---------------------------------
  void _onPlatformViewCreated(int viewId) {
    _channel = MethodChannel('$_viewType/$viewId');
    _channel!.setMethodCallHandler(_onNativeCall);
    // 作っている間に変わった文書を渡し直す
    _channel!.invokeMethod<void>(_updateMethod, _document);
    if (_clearPending) {
      _clearPending = false;
      _clearSelection();
    }
  }

  // ---------------------------------
  // ネイティブ側からの知らせ
  // ---------------------------------
  Future<void> _onNativeCall(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case _toggleBlockMethod:
        widget.onToggleSelection(call.arguments as int);
      case _thumbMethod:
        final thumb = call.arguments as Map;
        widget.onThumbChanged((
          memoId: thumb['id'] as int,
          y: (thumb['y'] as num).toDouble(),
          scrolling: thumb['scrolling'] == true,
        ));
    }
  }

  // ---------------------------------
  // ネイティブ側へ渡す文書（ブロックは古い順）
  // ---------------------------------
  Map<String, Object?> _buildDocument() {
    final blocks = [
      for (final memo in widget.memos.reversed)
        {
          'id': memo.id,
          'text': memo.content,
          'selected': widget.selectedIds.contains(memo.id),
        },
    ];
    return {
      'blocks': blocks,
      'fontSize': MediaQuery.textScalerOf(context).scale(_bodyFontSize),
      'textColor': AppColors.onSurface.toARGB32(),
      'copySeparator': _copySeparator,
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
    // 一覧の上の操作（スクロール・文字選択・丸のタップ）は、Flutter 側で取り合わずにすべて渡す
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
