import 'package:flutter/material.dart';
import 'package:momeo/widgets/selection_action_button.dart';

// スイッチで出入り（フェードイン・即時消滅）を、ボタンのタップで
// 退場シーケンス（disabled → アイコン回転 → 即時消滅）を確認できる
class WidgetsSelectionActionButtonSection extends StatefulWidget {
  const WidgetsSelectionActionButtonSection({super.key});

  @override
  State<WidgetsSelectionActionButtonSection> createState() =>
      _WidgetsSelectionActionButtonSectionState();
}

class _WidgetsSelectionActionButtonSectionState
    extends State<WidgetsSelectionActionButtonSection> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            SwitchListTile(
              title: const Text('表示（カード選択中の想定）'),
              value: _visible,
              onChanged: (value) => setState(() => _visible = value),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'タップすると実際の利用と同じく、アイコンが1回転してから'
                '一瞬で消える（コピーはしない）',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        // 実際の画面と同じく右下に重ねて表示する
        Positioned(
          right: 16,
          bottom: 16,
          child: SelectionActionButton(
            visible: _visible,
            icon: Icons.copy,
            // タップ時は実際の利用と同じく「選択が解除された」状態に戻す
            onPressed: () => setState(() => _visible = false),
          ),
        ),
      ],
    );
  }
}
