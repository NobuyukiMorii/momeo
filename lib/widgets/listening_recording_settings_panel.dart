import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_radius.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/models/recording_scope.dart';
import 'package:momeo/providers/settings_providers.dart';
import 'package:momeo/widgets/dot.dart';
import 'package:momeo/widgets/recording_option_cards.dart';

// ============================================================
// ListeningRecordingSettingsPanel — 画面の上端から下りてくる、録音設定パネル
//
//   閉じている間は、いつ録音するかを示す状態行1行だけが見えている。
//   状態行を押すと選択肢のカードが下へ滑り出し、検索フィールドやボイスカードの
//   上に覆いかぶさる（下にあるものは押し下げない）。
//
//   画面の上端とパネルの左右は常に線で囲む。開いている間は、
//     ・下の線を開き具合に合わせて少しずつ濃くし、下の角も少しずつ丸める
//     ・パネルの外を触ると閉じる（覆われた検索フィールドやボイスカードは反応しない）
//
//   パネルの外に受け皿を敷くため、画面全体に広げて置く（Positioned.fill）。
//   閉じている間は状態行の外に何も置かないので、下の検索フィールドや一覧はそのまま触れる。
// ============================================================

// ---------------------------------
// 定数: 高さ
// ---------------------------------

// 状態行の高さの下限（ふつうの文字サイズで、caption の行の高さ 18 がぎりぎり収まる）
const _stateRowMinHeight = 28.0;

// 状態行の文言の上下に取る余白の合計（ふつうの文字サイズでは 18 + 10 = 28）
const _stateRowVerticalSpace = 10.0;

// 選択肢の面の上下の余白（上は状態行との間、下はパネルの下の線との間）
const _optionsPaddingTop = AppSpacing.s;
const _optionsPaddingBottom = AppSpacing.l;

// ---------------------------------
// 定数: 見た目
// ---------------------------------

// パネルを囲む線の太さと、開いたときの下の角の丸み（検索フィールドの枠に揃える）
const _frameBorderWidth = 3.0;
const _frameCornerRadius = AppRadius.l;

// 中身の左右の余白（線の内側に余白を取る。検索フィールドの中身とも左端が揃う）
const _contentPadding = AppSpacing.l + _frameBorderWidth;

// パネルを囲む線
const _frameSide = BorderSide(
  color: AppColors.onSurface,
  width: _frameBorderWidth,
);

// 安全領域の見た目（左右と、画面の上端に線を引く。下は状態行へ続くので引かない）
const _safeAreaDecoration = BoxDecoration(
  color: AppColors.surface,
  border: Border(left: _frameSide, top: _frameSide, right: _frameSide),
);

// 開いているかを示す山形の大きさ
const _chevronSize = 18.0;

// ---------------------------------
// 定数: 動き
// ---------------------------------

// 選択肢の面を開き閉じする時間
const _panelDuration = Duration(milliseconds: 250);

// 位置に関わらず閉じてしまう、上へ払う速さ（px/秒）
const _closeFlingVelocity = 400.0;

// ---------------------------------
// 閉じているときのパネルの高さ（安全領域は含まない。状態行1行ぶん）
//   文字サイズの設定で文言の行が高くなったら、切れないようにその分だけ伸ばす
// ---------------------------------
double listeningRecordingSettingsPanelCollapsedHeightOf(BuildContext context) {
  // --- 文字サイズの設定を反映した、文言1行の高さ
  const textStyle = AppTextStyles.caption;
  final scaledFontSize = MediaQuery.textScalerOf(
    context,
  ).scale(textStyle.fontSize!);
  final lineHeight = scaledFontSize * textStyle.height!;
  // --- 上下の余白を足す（ふつうの文字サイズより低くはしない）
  return max(_stateRowMinHeight, lineHeight + _stateRowVerticalSpace);
}

// ---------------------------------
// クラス本体
// ---------------------------------
class ListeningRecordingSettingsPanel extends ConsumerStatefulWidget {
  const ListeningRecordingSettingsPanel({super.key});

  @override
  ConsumerState<ListeningRecordingSettingsPanel> createState() =>
      _ListeningRecordingSettingsPanelState();
}

// ---------------------------------
// 状態
// ---------------------------------
class _ListeningRecordingSettingsPanelState
    extends ConsumerState<ListeningRecordingSettingsPanel>
    with SingleTickerProviderStateMixin {
  // 選択肢の面の開き具合（0 = 閉じきり、1 = 開ききり）
  late final AnimationController _panelController;

  // 開き具合に緩急を付けた値（面の高さと山形の向きに使う）
  late final CurvedAnimation _panelAnimation;

  // ---------------------------------
  // コントローラを用意する
  // ---------------------------------
  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: _panelDuration,
    );
    _panelAnimation = CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOut,
    );
    // --- 開き始めと閉じきりで、受け皿を出し入れする
    _panelController.addStatusListener(_onPanelStatusChanged);
  }

  // ---------------------------------
  // 後片付け
  // ---------------------------------
  @override
  void dispose() {
    _panelController.removeStatusListener(_onPanelStatusChanged);
    _panelAnimation.dispose();
    _panelController.dispose();
    super.dispose();
  }

  // ---------------------------------
  // 開いているか（開き閉じの途中も含む）
  // ---------------------------------
  bool get _isOpen => !_panelController.isDismissed;

  // ---------------------------------
  // 開き閉じの状態が変わったとき
  // ---------------------------------
  void _onPanelStatusChanged(AnimationStatus status) {
    // 受け皿の有無は _isOpen から決まるので、描き直すだけでよい
    setState(() {});
  }

  // ---------------------------------
  // 選択肢の面の開き閉じ
  // ---------------------------------
  void _togglePanel() {
    _isOpen ? _closePanel() : _panelController.forward();
  }

  // ---------------------------------
  // 選択肢の面を閉じる
  // ---------------------------------
  void _closePanel() {
    _panelController.reverse();
  }

  // ---------------------------------
  // パネルを上へ払ったら閉じる（下へ払っても開かない）
  // ---------------------------------
  void _onVerticalDragEnd(DragEndDetails details) {
    // --- 離した瞬間の縦の速さ（上向きが負）
    final velocity = details.primaryVelocity ?? 0;
    // --- 勢いよく上へ払ったときだけ閉じる
    if (velocity < -_closeFlingVelocity) _closePanel();
  }

  // ---------------------------------
  // 開いているかを示す山形（開くと半回転して上を向く）
  // ---------------------------------
  Widget _buildChevron() {
    return RotationTransition(
      turns: _panelAnimation.drive(Tween(begin: 0.0, end: 0.5)),
      child: const Icon(
        Icons.keyboard_arrow_down,
        size: _chevronSize,
        color: AppColors.onSurface,
      ),
    );
  }

  // ---------------------------------
  // 状態行（いつ録音するかを、点滅するドットと文言で示す）
  // ---------------------------------
  Widget _buildStateRow() {
    // --- 今どの範囲で録音する設定か
    final backgroundRecording = ref.watch(backgroundRecordingProvider).value;
    final scope = RecordingScope.of(
      isBackgroundRecordingEnabled: backgroundRecording?.isEnabled ?? false,
    );

    return GestureDetector(
      onTap: _togglePanel,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: listeningRecordingSettingsPanelCollapsedHeightOf(context),
        padding: const EdgeInsets.symmetric(horizontal: _contentPadding),
        child: Row(
          children: [
            // --- ドット（どちらの範囲でも録音は続くので点滅させる）
            Dot(color: scope.dotColor),
            const SizedBox(width: AppSpacing.s),
            // --- 今選んでいる範囲の文言
            Expanded(
              child: Text(
                scope.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // --- 山形（押せる場所だと伝える役目も兼ねる）
            _buildChevron(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------
  // 選択肢の面（閉じている間は高さ 0。開くとカードが下へ滑り出す）
  // ---------------------------------
  Widget _buildOptions() {
    return AnimatedBuilder(
      animation: _panelAnimation,
      // カードの周りの余白を触っても閉じられるようにする。
      // カードそのもののタップはカード側が受け取る（内側の反応が優先される）
      child: GestureDetector(
        onTap: _closePanel,
        behavior: HitTestBehavior.opaque,
        child: const Padding(
          padding: EdgeInsets.fromLTRB(
            _contentPadding,
            _optionsPaddingTop,
            _contentPadding,
            _optionsPaddingBottom,
          ),
          child: RecordingOptionCards(),
        ),
      ),
      builder: (context, options) {
        // --- 閉じきっている間は中身ごとツリーから外す
        if (_panelController.isDismissed) return const SizedBox.shrink();
        // カードの下辺を箱の下辺に留めたまま箱を伸ばすので、カードは箱と一緒に
        // 下がりながら上から姿を現す。はみ出した上辺は状態行を隠さないよう切る
        return ClipRect(
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: _panelAnimation.value,
            child: options,
          ),
        );
      },
    );
  }

  // ---------------------------------
  // 状態行と選択肢の面を囲む枠
  //
  //   左右の線はいつも濃いまま。下の線は開き具合に合わせて少しずつ濃くし、
  //   下の角も少しずつ丸める（閉じた形から開いた形へ一気に切り替えない）
  // ---------------------------------
  Widget _buildFrame(Widget body, {required double openProgress}) {
    // --- 開き具合に合わせた、下の角の丸み
    final bottomCorners = BorderRadius.vertical(
      bottom: Radius.circular(_frameCornerRadius * openProgress),
    );
    // --- 開き具合に合わせて濃くなる線
    final fadingSide = BorderSide(
      color: AppColors.onSurface.withValues(alpha: openProgress),
      width: _frameBorderWidth,
    );

    return Stack(
      children: [
        // --- 白い面と、いつも濃い左右の線
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: const Border(left: _frameSide, right: _frameSide),
            borderRadius: bottomCorners,
          ),
          child: body,
        ),
        // --- 左右と下の線を、開き具合のぶんだけ濃く重ねる（閉じきっている間は重ねない）
        if (openProgress > 0)
          Positioned.fill(
            // 線を重ねるだけなので、触った反応は下の中身へ通す
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: fadingSide,
                    right: fadingSide,
                    bottom: fadingSide,
                  ),
                  borderRadius: bottomCorners,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------
  // パネル本体（安全領域と、枠で囲んだ状態行・選択肢の面）
  // ---------------------------------
  Widget _buildPanelBody(double safeAreaTop) {
    return GestureDetector(
      // パネルのどこを上へ払っても閉じられるようにする
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Column(
        // 子は既定では横に伸びないため、明示して画面幅いっぱいに広げる
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- 安全領域は、左右と上を線で囲む
          DecoratedBox(
            decoration: _safeAreaDecoration,
            child: SizedBox(height: safeAreaTop),
          ),
          // --- 状態行と選択肢の面（開くと選択肢の面のぶんだけ背が伸びる）
          //     線が付いても中身の位置が動かないよう、余白は中身の側で持つ
          AnimatedBuilder(
            animation: _panelAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_buildStateRow(), _buildOptions()],
            ),
            builder: (context, body) =>
                _buildFrame(body!, openProgress: _panelAnimation.value),
          ),
        ],
      ),
    );
  }

  // ---------------------------------
  // 受け皿（開いている間、パネルの外を覆う）
  //
  //   触った時点で閉じ、その触り方は下の検索フィールドやボイスカードへ通さない
  // ---------------------------------
  Widget _buildBarrier() {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _closePanel(),
    );
  }

  // ---------------------------------
  // 組み立て
  // ---------------------------------
  @override
  Widget build(BuildContext context) {
    // 安全領域の上端
    final safeAreaTop = MediaQuery.paddingOf(context).top;

    return Stack(
      children: [
        // --- 開いている間だけ、パネルの外に受け皿を敷く
        if (_isOpen) Positioned.fill(child: _buildBarrier()),
        // --- パネル本体は画面の上端に貼り付ける
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildPanelBody(safeAreaTop),
        ),
      ],
    );
  }
}
