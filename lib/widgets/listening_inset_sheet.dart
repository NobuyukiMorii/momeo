import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:momeo/database/app_database.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_radius.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/providers/settings_providers.dart';
import 'package:momeo/widgets/dot.dart';
import 'package:momeo/widgets/listening_header.dart';

// ============================================================
// 画面下端の領域をつまみで広げ縮めするシート
// ============================================================

// ---------------------------------
// 定数: 高さ関連
// ---------------------------------

// 閉じているときに覗かせる高さ（安全領域より上のぶん）
const _peekHeight = 64.0;

// シート上辺の枠線の太さ（帯の高さはこのぶん削られる）
const _sheetBorderWidth = 1.0;

// 開き切ったとき、ヘッダーとの間に残す余白
const _openTopMargin = AppSpacing.s;

// 開き切ったときの高さが、ヘッダーの下に残る範囲のどれだけを占めるか
const _openHeightRatio = 0.5;

// ブラックボードのエリア（余白・上の一言・ブラックボード本体）が潰れずに収まる高さ
const _blackboardAreaMinHeight = 100.0;

// 録音の選択肢のエリアが潰れずに収まる高さ
// （文字の折り返しで伸びても足りるよう、実際のカードより多めに取る）
const _optionAreaMinHeight = 200.0;

// 操作ボタンを置く、シート最下部のエリアの高さ
const _bottomAreaHeight = 64.0;

// ---------------------------------
// 定数: 画面に出る文言
// ---------------------------------

// バックグラウンド録音の状態を伝える、帯の文言
const _statusLabelEnabled = 'ほかのアプリを使っていても録音';
const _statusLabelDisabled = 'このアプリを使っている時だけ録音';

// バックグラウンド録音の選択肢（無効側・有効側）
const _optionTitleDisabled = 'このアプリを使っている時だけ録音';
const _optionDescriptionDisabled = 'アプリがバックグラウンドに移ると録音を止め、フォアグラウンドに戻ると再開します。';
const _optionTitleEnabled = 'ほかのアプリを使っていても録音';
const _optionDescriptionEnabled = 'ほかのアプリを使っている間や画面を消している間も、マイクで音声を録り続けます。アプリを終了すると止まります。';

// 初回に有効へ切り替えるとき出す、開示と同意のダイアログの文言
const _backgroundDisclosureTitle = 'ほかのアプリを使っていても録音しますか？';
const _backgroundDisclosureMessage =
    'ほかのアプリを使っている間や画面を消している間も、マイクで音声を録り続けます。\n\n'
    '録音した音声と文字起こしはこの端末の中だけに保存され、外部に送信されることはありません。\n\n'
    'この設定はいつでも解除できます。';
const _backgroundDisclosureCancelLabel = 'キャンセル';
const _backgroundDisclosureConfirmLabel = '有効にする';

// ブラックボードの上に出す一言（空のとき・空のまま触れたとき・コピーした直後）
const _emptyNoticeLabel = '選択したテキストが表示されます';
const _emptyTouchNoticeLabel = 'テキストを選択するとコピーできます';
const _copyNoticeLabel = 'クリップボードにコピーしました';

// 削除ボタンを押したときに出す確認ダイアログの文言
// （ボタン自体の文言は件数を含むので、_buildBottomArea で組み立てる）
const _deleteDialogTitle = '選択中のメモを削除しますか？';
const _deleteDialogMessage = '一度削除すると復元できません。';
const _deleteDialogCancelLabel = 'キャンセル';
const _deleteDialogConfirmLabel = '削除する';

// ---------------------------------
// 定数: 文字列のフォーマット
// ---------------------------------

// 選択件数の3桁区切り（1000 件を超えることはまず無いが、桁が読める形にしておく）
final _selectionCountFormat = NumberFormat('#,###');

// メモとメモのつなぎ目（空行1つ。コピーした文字列にもそのまま入る）
const _selectedMemoSeparator = '\n\n';

// ---------------------------------
// クラス本体
// ---------------------------------
class ListeningInsetSheet extends ConsumerStatefulWidget {
  const ListeningInsetSheet({
    super.key,
    required this.heightNotifier,
    required this.isCollapsed,
    required this.selectedMemos,
    required this.onClearSelection,
    required this.onDeleteSelection,
  });

  // 今のシートの高さ（安全領域を除いた、一覧を押し上げるぶん）
  final ValueNotifier<double> heightNotifier;

  // シートが畳んであるかどうか
  final bool isCollapsed;

  // 選択中のメモ（時系列順。古いものが先頭）
  final List<VoiceMemo> selectedMemos;

  // 帯の右側をタップしたときに、選択をすべて解除する
  final VoidCallback onClearSelection;

  // 削除を確認したときに、選択中のメモを DB ごと消す
  final Future<void> Function() onDeleteSelection;

  @override
  ConsumerState<ListeningInsetSheet> createState() =>
      _ListeningInsetSheetState();
}

// ---------------------------------
// 状態
// ---------------------------------
class _ListeningInsetSheetState extends ConsumerState<ListeningInsetSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _openController;

  // ---------------------------------
  // ドラッグの移動量を開き具合の割合へ換算する分母
  // ---------------------------------
  double _dragRange = 1.0;

  // ---------------------------------
  // 録音の選択肢を開いているか（起動のたびに閉じた状態から始める）
  // ---------------------------------
  bool _isOptionExpanded = false;

  // ---------------------------------
  // 少しの間だけ出している一言
  // ---------------------------------
  String? _transientNoticeLabel;

  // 文言を引っ込めるためのタイマー（続けて出したときは張り替える）
  Timer? _noticeTimer;

  // ---------------------------------
  // コントローラを用意し、高さの変化を外へ流す
  // ---------------------------------
  @override
  void initState() {
    // --- 親の初期化を先に済ませる
    super.initState();
    // --- 開き具合を動かすコントローラを用意する（開閉アニメーションの時間）
    _openController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    // --- 値が動くたびに、今の高さを外へ伝える
    _openController.addListener(_publishHeight);
  }

  // ---------------------------------
  // 畳んでおく指示を受け取る
  // ---------------------------------
  @override
  void didUpdateWidget(ListeningInsetSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // --- 検索フィールドの入力が始まったら
    if (widget.isCollapsed && !oldWidget.isCollapsed) {
      _collapseImmediately(); // 開いていたシートを閉じる
    }
  }

  // ---------------------------------
  // その場でシートを畳む
  // ---------------------------------
  void _collapseImmediately() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // --- バックグラウンド録音の選択肢カードを非表示にする
      setState(() => _isOptionExpanded = false);
      // --- アニメーションを挟まず、その場で閉じる
      _openController.value = 0;
    });
  }

  // ---------------------------------
  // 後片付け
  // ---------------------------------
  @override
  void dispose() {
    // --- 一言を引っ込めるタイマーを止める
    _noticeTimer?.cancel();
    // --- 高さの通知を止める
    _openController.removeListener(_publishHeight);
    // --- コントローラを破棄する
    _openController.dispose();
    // --- 親の後片付けを最後に行う
    super.dispose();
  }

  // ---------------------------------
  // 高さ
  // ---------------------------------
  double get _currentHeight => _peekHeight + _dragRange * _openController.value;

  // ---------------------------------
  // 今の高さを画面側へ伝える
  // ---------------------------------
  void _publishHeight() {
    // --- 閉じた高さに開いたぶんを足した値を渡す
    widget.heightNotifier.value = _currentHeight;
  }

  // ---------------------------------
  // 開閉
  // ---------------------------------
  void _open() => _openController.forward();

  void _close() {
    // --- バックグラウンド録音の選択肢カードを非表示にする
    setState(() => _isOptionExpanded = false);
    // --- シートを閉じる
    _openController.reverse();
  }

  // ---------------------------------
  // 録音の選択肢を開き閉じする
  // ---------------------------------
  void _toggleOption() {
    // --- バックグラウンド録音の選択肢カードの表示を切り替える
    setState(() => _isOptionExpanded = !_isOptionExpanded);
    // --- シートを開く
    _open();
  }

  // ---------------------------------
  // ドラッグ中は指の動きにそのまま追従させる
  // ---------------------------------
  void _onDragUpdate(DragUpdateDetails details) {
    // --- 上へ動かすと開く向きなので、移動量を引く
    _openController.value -= details.primaryDelta! / _dragRange;
  }

  // ---------------------------------
  // 指を離したら開くか閉じるかへ落ち着かせる
  // ---------------------------------
  void _onDragEnd(DragEndDetails details) {
    // 位置に関わらず開閉を決めてしまう速さ（px/秒）と、開く・閉じるを分ける位置
    const flingVelocity = 400.0;
    const openThreshold = 0.5;

    // --- 離した瞬間の縦の速さ（上向きが負）
    final velocity = details.primaryVelocity ?? 0;
    // --- 勢いがあれば位置に関わらずその向きへ
    if (velocity.abs() > flingVelocity) {
      velocity < 0 ? _open() : _close();
      return;
    }
    // --- 勢いが無ければ近いほうへ寄せる
    _openController.value > openThreshold ? _open() : _close();
  }

  // ---------------------------------
  // つまみ（ハンドル）
  // ---------------------------------
  Widget _buildHandle() {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.onSurface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    );
  }

  // ---------------------------------
  // 帯（閉じていても見えている、シートの上端）
  // ---------------------------------
  Widget _buildBand({required bool isBackgroundRecordingEnabled}) {
    // 選択肢の開閉を示す矢印の大きさ
    const statusArrowSize = 18.0;

    return SizedBox(
      height: _peekHeight - _sheetBorderWidth,
      child: Column(
        children: [
          // --- 中央のつまみ
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
            child: _buildHandle(),
          ),
          // --- つまみの下の余りを、左右の表示で分け合う
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ---------------------------------
                  // 左: バックグラウンド録音の状態
                  // ---------------------------------
                  GestureDetector(
                    onTap: _toggleOption,
                    behavior: HitTestBehavior.opaque,
                    // 指で押しやすいよう、上下にも当たり判定を広げる
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.s,
                      ),
                      child: Row(
                        children: [
                          // ---------------------------------
                          // ドット（どちらの状態でも録音は続くので点滅させる）
                          // ---------------------------------
                          Dot(
                            // 画面を離れても録音が続く有効側は強い注意の色、アプリ内だけの無効側は弱い注意の色にする
                            color: isBackgroundRecordingEnabled
                                ? AppColors.caution
                                : AppColors.notice,
                          ),
                          const SizedBox(width: AppSpacing.s),
                          // ---------------------------------
                          // 文言
                          // ---------------------------------
                          Text(
                            isBackgroundRecordingEnabled
                                ? _statusLabelEnabled
                                : _statusLabelDisabled,
                            style: AppTextStyles.caption,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          // ---------------------------------
                          // アコーディオンの矢印
                          // ---------------------------------
                          Icon(
                            _isOptionExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: statusArrowSize,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ---------------------------------
                  // 右: 選択の解除（0 件なら出さない）
                  // ---------------------------------
                  if (widget.selectedMemos.isNotEmpty)
                    GestureDetector(
                      onTap: widget.onClearSelection,
                      behavior: HitTestBehavior.opaque,
                      // 指で押しやすいよう、上下にも当たり判定を広げる
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.s,
                        ),
                        child: Text(
                          '${_selectionCountFormat.format(widget.selectedMemos.length)}件の選択を解除',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.link,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------
  // いつ録音するかの選択肢カード（2つ並ぶうちの1つ）
  // ---------------------------------
  Widget _buildBackgroundRecordingOption({
    required String title,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    // ---------------------------------
    // 枠線の太さ（選ばれていないとき・選ばれているとき）
    // ---------------------------------
    const normalBorderWidth = 1.5;
    const selectedBorderWidth = 3.0;
    final borderWidth = isSelected ? selectedBorderWidth : normalBorderWidth;

    // ---------------------------------
    // カードの内側の余白（枠線が太った分だけ削り、中身の位置を保つ）
    // ---------------------------------
    final contentPadding = AppSpacing.l - (borderWidth - normalBorderWidth);

    // ---------------------------------
    // 選択肢カード
    // ---------------------------------
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(contentPadding),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.l),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.outline,
            width: borderWidth,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              description,
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
  // 選択中のメモを1つの文字列にまとめる
  // ---------------------------------
  String get _selectedMemoText => widget.selectedMemos
      .map((memo) => memo.content)
      .join(_selectedMemoSeparator);

  // ---------------------------------
  // ブラックボードの上の通知メッセージ
  // ---------------------------------
  void _showNoticeBriefly(String label) {
    // 文言を出しておく時間
    const noticeDuration = Duration(milliseconds: 3600);
    // --- 文言を出しておく
    setState(() => _transientNoticeLabel = label);
    // --- 続けて出したときも、最後の1回から数えて引っ込める
    _noticeTimer?.cancel();
    // --- 文言を引っ込めるタイマーをセット
    _noticeTimer = Timer(noticeDuration, () {
      if (mounted) setState(() => _transientNoticeLabel = null);
    });
  }

  // ---------------------------------
  // メモをクリップボードにコピー
  // ---------------------------------
  void _copySelectedMemos() {
    // --- クリップボードにコピー
    Clipboard.setData(ClipboardData(text: _selectedMemoText));
    // --- コピーしたことを知らせる
    _showNoticeBriefly(_copyNoticeLabel);
  }

  // ---------------------------------
  // ブラックボードの上に出す一言（何も選んでいないときの案内と、コピーしたことの知らせ）
  // ---------------------------------
  Widget _buildNotice() {
    // 文言の出入りでブラックボードの位置が動かないよう、常に空けておく高さ
    const noticeHeight = 16.0;

    // 文字の大きさ（日時より少し大きくして読み取りやすくする）
    const noticeFontSize = 12.0;

    final hasSelection = widget.selectedMemos.isNotEmpty;

    // 少しの間だけ出す一言を優先し、無いときは選択中ならコピーの文言のまま消えていく
    final transientLabel = _transientNoticeLabel;
    final label =
        transientLabel ?? (hasSelection ? _copyNoticeLabel : _emptyNoticeLabel);

    // 何も選んでいない間はブラックボードの案内を出したままにする
    final isVisible = transientLabel != null || !hasSelection;

    return SizedBox(
      height: noticeHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Opacity(
          opacity: isVisible ? 1.0 : 0.0,
          child: Text(
            label,
            // 文字を大きくする設定でも2行にならないよう、1行に収めて末尾を省く
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.micro.copyWith(
              fontSize: noticeFontSize,
              color: AppColors.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------
  // ブラックボード（選択中のメモをまとめて映す黒い面）
  // ---------------------------------
  Widget _buildBlackboard() {
    // 押したままにしたとき、コピーと見なすまでの時間
    // （既定の長押し 500ms は待たされる感じが出るので短くする）
    const longPressDuration = Duration(milliseconds: 150);

    // 枠線の太さ（一覧のカードの細いほうに揃える）
    const borderWidth = 1.5;

    // ブラックボードに入れる本文があるか
    final hasSelection = widget.selectedMemos.isNotEmpty;

    // ---------------------------------
    // ジェスチャーイベントのハンドラー
    // ---------------------------------
    void handleTouch() {
      // --- 選択中のメモがあれば
      if (hasSelection) {
        // --- コピー
        _copySelectedMemos();
        return;
      }
      // --- 選択中のメモがなければ
      _showNoticeBriefly(_emptyTouchNoticeLabel); // ブラックボードの上に通知メッセージ
    }

    // ---------------------------------
    // ブラックボードのジェスチャーイベント
    // ---------------------------------
    final touchGestures = <Type, GestureRecognizerFactory>{
      // --- 押してすぐ離したとき
      TapGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            TapGestureRecognizer.new,
            (recognizer) => recognizer.onTap = handleTouch,
          ),
      // --- 押したまま留めたとき
      LongPressGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(duration: longPressDuration),
            (recognizer) => recognizer.onLongPress = handleTouch,
          ),
    };

    // ---------------------------------
    // ブラックボードを組み立てて返す
    // ---------------------------------
    return RawGestureDetector(
      gestures: touchGestures,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.l),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppRadius.l),
          border: Border.all(
            color: AppColors.primary,
            width: borderWidth,
          ),
        ),
        child: hasSelection
            ? SingleChildScrollView( // スクロール
                child: Text(
                  _selectedMemoText,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.onPrimary,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  // ---------------------------------
  // 削除の確認ダイアログ
  // ---------------------------------
  Future<void> _confirmAndDeleteSelectedMemos() async {
    // 本文とボタンの文字の大きさ（caption の 12 では小さいので上げる）
    const dialogFontSize = 15.0;

    final isConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _deleteDialogTitle,
          style: AppTextStyles.button.copyWith(color: AppColors.onSurface),
        ),
        content: Text(
          _deleteDialogMessage,
          style: AppTextStyles.caption.copyWith(
            fontSize: dialogFontSize,
            color: AppColors.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              _deleteDialogCancelLabel,
              style: AppTextStyles.caption.copyWith(
                fontSize: dialogFontSize,
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              _deleteDialogConfirmLabel,
              style: AppTextStyles.caption.copyWith(
                fontSize: dialogFontSize,
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (isConfirmed != true || !mounted) return;
    await widget.onDeleteSelection();
  }

  // ---------------------------------
  // バックグラウンド録音の開示と同意のダイアログ
  // ---------------------------------
  Future<bool> _confirmBackgroundRecordingDisclosure() async {

    // ---------------------------------
    // ダイアログの文字の大きさ
    // ---------------------------------
    const dialogFontSize = 15.0;

    // ---------------------------------
    // ダイアログを表示
    // ---------------------------------
    final isConfirmed = await showDialog<bool>(
      context: context,
      // 外側のタップで閉じさせず、どちらかを選んでもらう
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _backgroundDisclosureTitle,
          style: AppTextStyles.button.copyWith(color: AppColors.onSurface),
        ),
        content: Text(
          _backgroundDisclosureMessage,
          style: AppTextStyles.caption.copyWith(
            fontSize: dialogFontSize,
            color: AppColors.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              _backgroundDisclosureCancelLabel,
              style: AppTextStyles.caption.copyWith(
                fontSize: dialogFontSize,
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              _backgroundDisclosureConfirmLabel,
              style: AppTextStyles.caption.copyWith(
                fontSize: dialogFontSize,
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    // ---------------------------------
    // 同意が得られたか
    // ---------------------------------
    return isConfirmed == true;
  }

  // ---------------------------------
  // シート最下部の操作エリア
  // ---------------------------------
  Widget _buildBottomArea() {
    // 削除ボタンの文字の大きさ（caption の 12 では小さいので上げる）
    const deleteLabelFontSize = 15.0;

    return Container(
      height: _bottomAreaHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
      alignment: Alignment.centerRight,
      child: widget.selectedMemos.isEmpty
          ? null
          // ---------------------------------
          // 削除ボタン
          // ---------------------------------
          : GestureDetector(
              onTap: _confirmAndDeleteSelectedMemos,
              behavior: HitTestBehavior.opaque,
              // 指で押しやすいよう、文字のまわりに当たり判定を広げる
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s,
                  vertical: AppSpacing.s,
                ),
                child: Text(
                  '選択中の${_selectionCountFormat.format(widget.selectedMemos.length)}件を削除',
                  style: AppTextStyles.caption.copyWith(
                    fontSize: deleteLabelFontSize,
                    color: AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
    );
  }

  // ---------------------------------
  // シート上側
  // ---------------------------------
  Widget _buildBackgroundRecordingSection({
    required bool isBackgroundRecordingEnabled,
    required bool hasEverEnabledBackgroundRecording,
  }) {
    // ---------------------------------
    // 選んだほうを設定として保存する
    // ---------------------------------
    Future<void> select(bool isEnabled) async {
      // --- 初めて有効にするときだけ開示が要る
      final needsDisclosure = isEnabled && !hasEverEnabledBackgroundRecording;
      // --- 同意が得られなければ何もしない
      if (needsDisclosure && !await _confirmBackgroundRecordingDisclosure()) {
        return;
      }
      // --- 設定を保存
      await ref
          .read(backgroundRecordingProvider.notifier)
          .setEnabled(isEnabled);
    }

    // ---------------------------------
    // バックグラウンド録音設定の選択カード
    // ---------------------------------
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---------------------------------
          // バックグラウンド録音の無効
          // ---------------------------------
          Expanded(
            child: _buildBackgroundRecordingOption(
              title: _optionTitleDisabled,
              description: _optionDescriptionDisabled,
              isSelected: !isBackgroundRecordingEnabled,
              onTap: () => select(false),
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          // ---------------------------------
          // バックグラウンド録音の有効
          // ---------------------------------
          Expanded(
            child: _buildBackgroundRecordingOption(
              title: _optionTitleEnabled,
              description: _optionDescriptionEnabled,
              isSelected: isBackgroundRecordingEnabled,
              onTap: () => select(true),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------
  // 組み立て
  // ---------------------------------
  @override
  Widget build(BuildContext context) {

    // ---------------------------------
    // バックグラウンド録音の設定を取得
    // ---------------------------------
    final backgroundRecording = ref.watch(backgroundRecordingProvider).value;

    // ---------------------------------
    // 今バックグラウンド録音を有効にしているか
    // ---------------------------------
    final isBackgroundRecordingEnabled = backgroundRecording?.isEnabled ?? false;

    // ---------------------------------
    // 一度でも有効にしたか
    // ---------------------------------
    final hasEverEnabledBackgroundRecording = backgroundRecording?.hasEverEnabled ?? false;

    // ---------------------------------
    // 安全領域
    // ---------------------------------
    final safeArea = MediaQuery.paddingOf(context);

    // ---------------------------------
    // 安全領域の下端
    // ---------------------------------
    final safeBottom = safeArea.bottom;

    // ---------------------------------
    // ヘッダーの下に残る、シートが伸びる範囲
    // ---------------------------------
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        safeArea.top -
        safeBottom -
        listeningHeaderHeight -
        _openTopMargin;

    // ---------------------------------
    // シートを開き切ったときの高さ
    // ---------------------------------
    final openHeight = math.max(
      availableHeight * _openHeightRatio,
      _peekHeight +
          _optionAreaMinHeight +
          _blackboardAreaMinHeight +
          _bottomAreaHeight,
    );

    // ---------------------------------
    // 開き具合の範囲を計算
    // ---------------------------------
    _dragRange = openHeight - _peekHeight;

    // ---------------------------------
    // 初回と画面サイズの変化に合わせて高さを伝え直す
    // ---------------------------------
    WidgetsBinding.instance.addPostFrameCallback((_) => _publishHeight());

    // ---------------------------------
    // 下端に貼り付いたシート本体（高さが開き具合に追従）
    // ---------------------------------
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedBuilder(
        // --- 開き具合が動くたびに作り直す ---
        animation: _openController,
        // --- 開き具合を高さに変えて、シートの背丈を決める ---
        builder: (context, content) {

          // -------------------------------------------------------------
          // 高さの最小値を計算
          // -------------------------------------------------------------
          final minContentHeight =
              _peekHeight -
              _sheetBorderWidth +
              (_isOptionExpanded ? _optionAreaMinHeight : 0) +
              _blackboardAreaMinHeight +
              _bottomAreaHeight;

          // -------------------------------------------------------------
          // 高さの最大値を計算
          // -------------------------------------------------------------
          final contentHeight = math.max(
            _currentHeight - _sheetBorderWidth,
            minContentHeight,
          );
          return SizedBox(
            height: _currentHeight + safeBottom,
            child: GestureDetector(
              // --- ドラッグ中は指に追従させる
              onVerticalDragUpdate: _onDragUpdate,
              // --- 指を離したら開くか閉じるかへ落ち着かせる
              onVerticalDragEnd: _onDragEnd,
              // --- シートの見た目 ---
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  // borderRadius: BorderRadius.vertical(
                  //   top: Radius.circular(AppRadius.xl),
                  // ),
                  border: Border(
                    top: BorderSide(
                      color: AppColors.onSurface,
                      width: _sheetBorderWidth,
                    ),
                  ),
                ),
                padding: EdgeInsets.only(bottom: safeBottom),
                // 閉じている間、帯からはみ出す中身を切り落とす
                clipBehavior: Clip.hardEdge,
                // シートが低いときは中身を縮めず、上を残して下へはみ出させて隠す
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: contentHeight,
                    maxHeight: contentHeight,
                    child: content,
                  ),
                ),
              ),
            ),
          );
        },
        // ---------------------------------
        // シートの中身
        // ---------------------------------
        child: Column(
          children: [
            // ---------------------------------
            // シートを閉じていても見えるエリア
            // ---------------------------------
            _buildBand(
              isBackgroundRecordingEnabled: isBackgroundRecordingEnabled,
            ),
            // ---------------------------------
            // シートを開いたときに見えるエリア
            // ---------------------------------
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.l,
                  AppSpacing.s,
                  AppSpacing.l,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ---------------------------------
                    // 録音の選択肢
                    // ---------------------------------
                    if (_isOptionExpanded)
                      _buildBackgroundRecordingSection(
                        isBackgroundRecordingEnabled:
                            isBackgroundRecordingEnabled,
                        hasEverEnabledBackgroundRecording:
                            hasEverEnabledBackgroundRecording,
                      ),
                    // ---------------------------------
                    // ブラックボードの上に出す一言
                    // ---------------------------------
                    const SizedBox(height: AppSpacing.xs),
                    _buildNotice(),
                    // ---------------------------------
                    // ブラックボード
                    // ---------------------------------
                    const SizedBox(height: AppSpacing.s),
                    Expanded(child: _buildBlackboard()),
                  ],
                ),
              ),
            ),
            // ---------------------------------
            // 操作ボタンのエリア
            // ---------------------------------
            _buildBottomArea(),
          ],
        ),
      ),
    );
  }
}
