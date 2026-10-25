import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/pages/splash_page.dart';
import 'package:momeo/providers/stt_providers.dart';
import 'package:momeo/stt/stt_audio_worker.dart';
import 'package:momeo/widgets/activity_dots_text.dart';
import 'package:momeo/widgets/intro_setting_layout.dart';
import 'package:momeo/widgets/content_slide_switcher.dart';

// ---------------------------------
// 待ち画面の5フェーズ
// ---------------------------------
enum PreparationPhase {
  /// エンジンの準備中（OS の文字起こしの確かめ・音声 isolate の立ち上げ）
  loading,

  /// エンジン初期化に失敗し、自動再試行を待っている状態
  retrying,

  /// 連続失敗が閾値を超え、ユーザーに再起動を促す状態
  tryRestarting,

  /// OS の文字起こしが使えない端末。再試行しない
  unsupported,

  /// OS が言語のモデルをダウンロード中。入ったかを確かめ直しながら待つ
  downloadingLanguage,
}

// ---------------------------------
// 文字化エンジンの準備が終わるまでの待ち画面
// ---------------------------------
class PreparationGatePage extends ConsumerWidget {
  const PreparationGatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engineState = ref.watch(sttEngineProvider);
    final restartSuggested = ref.watch(sttRestartSuggestedProvider);

    final phase = _resolvePhase(engineState, restartSuggested);

    return Scaffold(
      body: IntroSettingLayout(
        title: DefaultTextStyle(
          style: AppTextStyles.headline.copyWith(color: AppColors.onSurface),
          child: ContentSlideSwitcher(
            contentKey: phase,
            child: _buildPhaseContent(phase),
          ),
        ),
      ),
    );
  }

  // ---------------------------------
  // エンジンの状態からフェーズを判定する
  // ---------------------------------
  PreparationPhase _resolvePhase(
    AsyncValue<SttAudioWorker> engineState,
    bool restartSuggested,
  ) {
    // ---------------------------------
    // 言語のモデルのダウンロード中（確かめ直しの最中も、表示を揺らさないよう同じフェーズにする）
    // ---------------------------------
    if (engineState.error is SttModelDownloadingError) {
      return PreparationPhase.downloadingLanguage;
    }

    // ---------------------------------
    // エンジン失敗中（再試行のisLoading中は除く。前回のエラーが残り続けるため）
    // ---------------------------------
    if (engineState.hasError && !engineState.isLoading) {
      if (engineState.error is SttUnsupportedError) {
        return PreparationPhase.unsupported;
      }
      return restartSuggested
          ? PreparationPhase.tryRestarting
          : PreparationPhase.retrying;
    }

    return PreparationPhase.loading;
  }

  // ---------------------------------
  // フェーズのコンテンツを組み立てる
  // ---------------------------------
  Widget _buildPhaseContent(PreparationPhase phase) {
    switch (phase) {
      case PreparationPhase.loading:
        return const Text(splashAppName);
      case PreparationPhase.retrying:
        return const ActivityDotsText('再試行しています');
      case PreparationPhase.tryRestarting:
        // 「処理中」ではなくユーザーへの依頼なので、動きは付けない
        return const Text('アプリを再起動してください');
      case PreparationPhase.unsupported:
        // 再起動しても変わらないお知らせなので、動きは付けない
        return const Text('この端末では使えません');
      case PreparationPhase.downloadingLanguage:
        return const ActivityDotsText('言語のモデルをダウンロードしています');
    }
  }
}
