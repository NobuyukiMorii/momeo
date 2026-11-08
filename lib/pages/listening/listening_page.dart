import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/providers/listening_providers.dart';
import 'package:momeo/widgets/listening_backdrop.dart';
import 'package:momeo/widgets/native_memo_list.dart';

// =====================================================================
// リスニング画面
// =====================================================================
class ListeningPage extends ConsumerStatefulWidget {
  const ListeningPage({super.key});

  @override
  ConsumerState<ListeningPage> createState() => _ListeningPageState();
}

class _ListeningPageState extends ConsumerState<ListeningPage> {
  // ---------------------------------
  // メモ一覧
  // ---------------------------------
  // 画面の上端から下端まで広げる。端の帯（ステータスバーなど）を避ける余白は、ネイティブ側が取る
  Widget _buildMemoList({required ListeningState listening}) {
    return Positioned.fill(
      child: NativeMemoList(
        memos: listening.memos,
        typingMemoId: listening.typeInMemoId,
        typeFrom: listening.typeInFrom,
        speakingDots: _speakingDots(listening),
        onDeleteText: _onDeleteText,
        onTypingComplete: _onTypingComplete,
      ),
    );
  }

  // 文字選択のメニューで「削除」が押されたら、選んだ範囲の文字をメモから消す
  void _onDeleteText(List<MemoTextRange> ranges) {
    unawaited(ref.read(listeningProvider.notifier).deleteTextRanges(ranges));
  }

  // 打ち出しの演出を使い切ったら、再表示で打ち直さないように知らせる
  void _onTypingComplete(int memoId) {
    if (!mounted) return;
    ref.read(listeningProvider.notifier).onTypingComplete(memoId);
  }

  // ---------------------------------
  // 発話中の「.」を出す場所
  // ---------------------------------
  // 発話が始まってから結果が届くまで出す。前の発話を打ち出している間は、打ち終わってから出す
  MemoSpeakingDots _speakingDots(ListeningState listening) {
    final waitingForText =
        listening.speechActive || listening.awaitingTranscription;
    if (!waitingForText || listening.typeInMemoId != null) {
      return MemoSpeakingDots.hidden;
    }
    // 追記先は発話の始まりで決まるので、出す場所も発話の途中では動かない
    return listening.appendTargetId != null
        ? MemoSpeakingDots.append
        : MemoSpeakingDots.newBlock;
  }

  @override
  Widget build(BuildContext context) {
    // ---------------------------------
    // リスニング状態
    // ---------------------------------
    final listening =
        ref.watch(listeningProvider).value ?? const ListeningState();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // ---------------------------------
          // 背景レイヤー
          // ---------------------------------
          Positioned.fill(
            child: ListeningBackdrop(
              levelReader: () =>
                  ref.read(listeningProvider.notifier).latestLevel,
            ),
          ),
          // ---------------------------------
          // メモ一覧
          // ---------------------------------
          _buildMemoList(listening: listening),
        ],
      ),
    );
  }
}
