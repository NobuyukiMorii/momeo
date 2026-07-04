import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/providers/stt_providers.dart';

// ============================================================
// エンジン常駐（Step 9）の動作確認セクション
//   アプリ全体で1つだけ持つ文字化エンジン（sttEngineProvider）の状態を映す。
//
//   ■ 確認したいこと
//   - 起動と同時に準備が始まり、ここを開いたときには（普通は）完了していること
//   - このセクションに出入りしても再ロードが走らないこと
//     （エンジン識別番号が変わらない＝同じエンジンの使い回し）
//   - モデル未配置などの失敗が「失敗」として見えること
//
//   ※ このセクションは状態を映すだけで、自分ではエンジンを作らない。
//   ※ Android のDL進捗・再試行は「STT → モデル配置」セクションが担当。
// ============================================================

class SttEngineSection extends ConsumerWidget {
  const SttEngineSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final engine = ref.watch(sttEngineProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'アプリ全体で1つだけ持つ文字化エンジンの準備状態を表示します。\n'
          '準備は起動と同時に始まるため、ここを開く前に完了しているのが正常です。\n'
          'このセクションに出入りしてもエンジン識別番号が変わらなければ、'
          '同じエンジンが使い回されています。',
          style: theme.textTheme.bodyMedium,
        ),
        const Divider(height: 32),

        // ---------------------------------
        // 準備状態（AsyncValue の3状態をそのまま表示する）
        // ---------------------------------
        switch (engine) {
          // 完了：エンジン識別番号を添えて表示（出入りで変わらないことの確認用）
          AsyncData(:final value) => _StatusTile(
              icon: Icons.check_circle,
              color: Colors.green,
              title: '完了（エンジン保持中）',
              detail: 'エンジン識別番号: ${identityHashCode(value)}',
            ),
          // 失敗：原因を表示（再試行の導線は Step 11 で作る）
          AsyncError(:final error) => _StatusTile(
              icon: Icons.error,
              color: theme.colorScheme.error,
              title: '失敗',
              detail: '$error',
            ),
          // 準備中：DL待ち・メモリ読み込み中
          _ => const _StatusTile(
              icon: Icons.hourglass_top,
              color: Colors.orange,
              title: '準備中（DL待ち・メモリ読み込み中）',
              detail: 'モデルの詳細は「STT → モデル配置」で確認できます',
            ),
        },
      ],
    );
  }
}

// ---------------------------------
// 状態1件ぶんの表示（アイコン＋タイトル＋詳細）
// ---------------------------------
class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
