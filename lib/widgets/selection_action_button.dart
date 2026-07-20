import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';

// ============================================================
// SelectionActionButton — カード選択中に現れる丸形の操作ボタン
//
//   コピー・削除など「選択したカードへの操作」を担う丸ボタンの共通ウィジェット。
//   出入りとタップ反応の演出をここに閉じる。
//   - 表示: 下からせり上がりながらフェードイン
//   - 非表示: 一瞬で消える
//   - タップ: 即座に disabled → アイコンが1回転 → 0.1秒おいて一瞬で消える
//   フェードイン中とタップ後はタップを受け付けない
// ============================================================

// ボタンの直径
const _buttonSize = 56.0;

// 登場時のフェードイン時間（下からのスライドも同じ時間で進む）
const _fadeInDuration = Duration(milliseconds: 250);

// 登場時に下からせり上がる距離
const _slideDistance = 24.0;

// タップ後のアイコン回転（1回転）の時間
const _rotationDuration = Duration(milliseconds: 500);

// 回転し終えてから消すまでの間
const _hideDelay = Duration(milliseconds: 100);

// 枠線の太さ（選択中カードの外枠と揃える）
const _borderWidth = 3.0;

class SelectionActionButton extends StatefulWidget {
  const SelectionActionButton({
    super.key,
    required this.visible,
    required this.icon,
    required this.onPressed,
  });

  // true になるとフェードインで現れ、false になると一瞬で消える
  final bool visible;

  // 円の中に表示するアイコン
  final IconData icon;

  // タップ成立時の通知。この直後からボタンは退場シーケンスに入る
  final VoidCallback onPressed;

  @override
  State<SelectionActionButton> createState() => _SelectionActionButtonState();
}

class _SelectionActionButtonState extends State<SelectionActionButton>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final AnimationController _slideController;
  late final AnimationController _rotationController;
  late final CurvedAnimation _slideAnimation;
  late final CurvedAnimation _rotationAnimation;

  // タップ後の退場シーケンス中か（この間は visible の変化より退場を優先する）
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: _fadeInDuration,
    );
    _slideController = AnimationController(
      vsync: this,
      duration: _fadeInDuration,
    );
    _rotationController = AnimationController(
      vsync: this,
      duration: _rotationDuration,
    );
    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    );
    _rotationAnimation = CurvedAnimation(
      parent: _rotationController,
      curve: Curves.easeInOut,
    );
    if (widget.visible) _show();
  }

  @override
  void didUpdateWidget(SelectionActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    // タップ後の退場中は出入りを触らない（退場し切ってから visible を見て出直す）
    if (_pressed) return;
    if (widget.visible) {
      _show();
    } else {
      _hide();
    }
  }

  @override
  void dispose() {
    _slideAnimation.dispose();
    _rotationAnimation.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  // 下からのスライド＋フェードインで登場する
  void _show() {
    _slideController.forward(from: 0.0);
    _fadeController.forward(from: 0.0);
  }

  // アニメーションなしで一瞬で消す
  void _hide() {
    _fadeController.value = 0.0;
  }

  // フェードインの途中とタップ後はタップを受け付けない
  bool get _isPressable =>
      !_pressed && widget.visible && _fadeController.isCompleted;

  // ---------------------------------
  // タップ後の退場シーケンス
  // ---------------------------------
  // 即座に disabled にして連打を防ぎ、アイコンを1回転させたあと、
  // 少しだけ間を置いてから一瞬で消す。
  // 回転中に新しい選択が始まっていたら、最後にもう一度登場し直す
  Future<void> _handleTap() async {
    if (!_isPressable) return;
    _pressed = true;
    widget.onPressed();

    await _rotationController.forward(from: 0.0);
    if (!mounted) return;
    await Future<void>.delayed(_hideDelay);
    if (!mounted) return;

    _hide();
    _rotationController.value = 0.0;
    _pressed = false;
    if (widget.visible) _show();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_fadeController, _slideAnimation]),
      builder: (context, child) {
        // 完全に消えている間はツリーから外す（下へのタップも素通しになる）
        if (_fadeController.isDismissed) return const SizedBox.shrink();
        return Opacity(
          opacity: _fadeController.value,
          child: Transform.translate(
            offset: Offset(0, _slideDistance * (1 - _slideAnimation.value)),
            child: child,
          ),
        );
      },
      // 見えている間はタップを常に吸収し、下のカードには届かせない
      // （押せない間は吸収するだけで何もしない）
      child: GestureDetector(
        onTap: _handleTap,
        child: Container(
          width: _buttonSize,
          height: _buttonSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.onSurface, width: _borderWidth),
          ),
          child: RotationTransition(
            turns: _rotationAnimation,
            child: Icon(widget.icon, color: AppColors.onSurface),
          ),
        ),
      ),
    );
  }
}
