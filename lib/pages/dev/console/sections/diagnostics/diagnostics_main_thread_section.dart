import 'package:flutter/material.dart';
import 'package:momeo/diagnostics/main_thread_watchdog.dart';

// ============================================================
// メインスレッドの詰まり（MainThreadWatchdog の記録）を一覧するセクション
//   起動からの累計で、閾値を超えて止まった時刻と長さを新しい順に並べる。
// ============================================================

class DiagnosticsMainThreadSection extends StatelessWidget {
  const DiagnosticsMainThreadSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<List<MainThreadStall>>(
      valueListenable: MainThreadWatchdog.instance.stalls,
      builder: (context, stalls, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'メインスレッドが 0.7 秒以上止まった回数と長さです。\n'
              '5 秒を超えると Android は「応答していません」を出します。',
              style: theme.textTheme.bodyMedium,
            ),
            const Divider(height: 32),
            Text('検出 ${stalls.length} 件（新しい順）',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (stalls.isEmpty)
              Text(
                'まだ検出はありません',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final stall in stalls)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatTime(stall.at),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        '${stall.duration.inMilliseconds} ms',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: stall.duration.inSeconds >= 5
                              ? theme.colorScheme.error
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        );
      },
    );
  }

  String _formatTime(DateTime at) {
    final hour = at.hour.toString().padLeft(2, '0');
    final minute = at.minute.toString().padLeft(2, '0');
    final second = at.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}
