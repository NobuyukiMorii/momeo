import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:momeo/database/app_database.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/widgets/typewriter_text.dart';

// ネイティブ側（NativeMemoListFactory）の登録名とそろえる、View の種類名
const _viewType = 'jp.momeo/native_memo_list';

// ネイティブ側へ呼び出すメソッド
const _updateMethod = 'update';
const _clearSelectionMethod = 'clearSelection';

// ネイティブ側から届くメソッド
const _thumbMethod = 'thumb';

// 本文の文字サイズ（端末の文字サイズの設定で拡大する前の値）
const _bodyFontSize = 18.0;

// 文字選択をブロックをまたいでコピーしたときの、ブロック同士の区切り
const _copySeparator = '\n\n';

// スクロールつまみの高さ（一覧の上端から測る）と、その高さにあるメモ
// scrolling は、指やつまみの操作でスクロールしたときだけ true（新しいメモで末尾へ移るときは false）
typedef MemoListThumb = ({int memoId, double y, bool scrolling});

// 発話中の気配として「.」を出す場所
// append: 最新のブロックの本文の続き / newBlock: 次のブロックの1行目
enum MemoSpeakingDots { hidden, append, newBlock }

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
    required this.controller,
    required this.onTypingComplete,
    required this.onThumbChanged,
    this.typingMemoId,
    this.typeFrom = 0,
    this.speakingDots = MemoSpeakingDots.hidden,
  });

  // 確定済みメモ一覧（新しい順）
  final List<VoiceMemo> memos;
  final NativeMemoListController controller;
  // 打ち出しの演出を使い切ったとき
  final ValueChanged<int> onTypingComplete;
  // スクロールつまみの高さ、またはその高さにあるメモが変わったとき
  final ValueChanged<MemoListThumb> onThumbChanged;
  // 打ち出し中のメモの id と、打ち出しを始める文字数
  final int? typingMemoId;
  final int typeFrom;
  final MemoSpeakingDots speakingDots;

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
  Map<String, Object?> _buildDocument(String typingText) {
    final blocks = [
      for (final memo in widget.memos.reversed)
        {
          'id': memo.id,
          // 打ち出し中のメモは、表示途中の本文を出す
          'text': memo.id == widget.typingMemoId ? typingText : memo.content,
          // 打ち出し中のメモは、打ち終わるまで文字選択の対象にしない
          'selectable': memo.id != widget.typingMemoId,
        },
    ];
    return {
      'blocks': blocks,
      'fontSize': MediaQuery.textScalerOf(context).scale(_bodyFontSize),
      'textColor': AppColors.onSurface.toARGB32(),
      'copySeparator': _copySeparator,
      'speakingDots': widget.speakingDots == MemoSpeakingDots.hidden
          ? null
          : widget.speakingDots.name,
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
    // 一覧の上の操作（スクロール・文字選択・つまみのドラッグ）は、Flutter 側で取り合わずにすべて渡す
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

  // 打ち出し途中の本文ごとに、文書を作り直して送る
  Widget _buildView(String typingText) {
    _document = _buildDocument(typingText);
    _sendDocumentIfChanged();
    return _buildPlatformView();
  }

  @override
  Widget build(BuildContext context) {
    final typingMemo = widget.memos
        .where((memo) => memo.id == widget.typingMemoId)
        .firstOrNull;
    // 部品の階層を保ち、打ち出しの開始・終了でネイティブ View を作り直さない
    return TypewriterText(
      typingMemo?.content ?? '',
      enabled: typingMemo != null,
      typeFrom: widget.typeFrom,
      onFinished: typingMemo == null
          ? null
          : () => widget.onTypingComplete(typingMemo.id),
      builder: _buildView,
    );
  }
}
