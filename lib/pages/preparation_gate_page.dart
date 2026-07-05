import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/platform/asset_pack_delivery.dart';
import 'package:momeo/providers/stt_providers.dart';
import 'package:momeo/stt/stt_transcriber.dart';
import 'package:momeo/widgets/activity_dots_text.dart';
import 'package:momeo/widgets/downloading_progress_text.dart';
import 'package:momeo/widgets/intro_setting_layout.dart';
import 'package:momeo/widgets/content_slide_switcher.dart';

// ---------------------------------
// 待ち画面の5フェーズ
// ---------------------------------
enum PreparationPhase {
  /// DL開始前・DL状態未取得。準備を始めた直後の状態
  gettingReady,

  /// モデルDLが進行中。DL%を表示する
  downloading,

  /// DLは完了、エンジンの初期化を待っている状態
  almostThere,

  /// エンジン初期化に失敗し、自動再試行を待っている状態
  retrying,

  /// 連続失敗が閾値を超え、ユーザーに再起動を促す状態
  tryRestarting,
}

// ---------------------------------
// 文字化エンジンの準備が終わるまでの待ち画面
// ---------------------------------
class PreparationGatePage extends ConsumerWidget {
  const PreparationGatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engineState = ref.watch(sttEngineProvider);
    final downloadState = ref.watch(sttModelDownloadStateProvider);
    final restartSuggested = ref.watch(sttRestartSuggestedProvider);

    final phase = _resolvePhase(engineState, downloadState, restartSuggested);

    return Scaffold(
      body: IntroSettingLayout(
        title: DefaultTextStyle(
          style: AppTextStyles.headline.copyWith(color: AppColors.onSurface),
          child: ContentSlideSwitcher(
            contentKey: phase,
            child: _buildPhaseContent(phase, downloadState),
          ),
        ),
      ),
    );
  }

  // ---------------------------------
  // エンジン・DLの状態からフェーズを判定する
  // ---------------------------------
  PreparationPhase _resolvePhase(
    AsyncValue<SttTranscriber> engineState,
    AsyncValue<AssetPackState> downloadState,
    bool restartSuggested,
  ) {
    // ---------------------------------
    // エンジン失敗中（再試行のisLoading中は除く。前回のエラーが残り続けるため）
    // ---------------------------------
    if (engineState.hasError && !engineState.isLoading) {
      return restartSuggested
          ? PreparationPhase.tryRestarting
          : PreparationPhase.retrying;
    }

    // ---------------------------------
    // DL状態が未取得 → DLがまだ始まる前と同じ扱い
    // ---------------------------------
    final download = downloadState.value;
    if (download == null) {
      return PreparationPhase.gettingReady;
    }

    // ---------------------------------
    // DL状態ごとに出し分ける
    //   completed には iOS のように自動DLが無い環境（常に完了扱い）も含まれる
    // ---------------------------------
    switch (download.phase) {
      case AssetPackPhase.notStarted:
        return PreparationPhase.gettingReady;
      case AssetPackPhase.downloading:
        return PreparationPhase.downloading;
      case AssetPackPhase.completed:
        return PreparationPhase.almostThere;
      case AssetPackPhase.failed:
        // エンジン側の失敗確定を待つ間もフェーズを揺らさないよう、同じ判定で出す
        return restartSuggested
            ? PreparationPhase.tryRestarting
            : PreparationPhase.retrying;
    }
  }

  // ---------------------------------
  // フェーズのコンテンツを組み立てる
  // ---------------------------------
  Widget _buildPhaseContent(
    PreparationPhase phase,
    AsyncValue<AssetPackState> downloadState,
  ) {
    switch (phase) {
      case PreparationPhase.gettingReady:
        return const ActivityDotsText('Getting ready');
      case PreparationPhase.downloading:
        // DL% は数字だけその場更新（フェーズが同じなのでスライドは起きない）
        final percent = ((downloadState.value?.progress ?? 0.0) * 100).round();
        return DownloadingProgressText(percent: percent);
      case PreparationPhase.almostThere:
        return const ActivityDotsText('Almost there');
      case PreparationPhase.retrying:
        return const ActivityDotsText('Retrying');
      case PreparationPhase.tryRestarting:
        // 「処理中」ではなくユーザーへの依頼なので、動きは付けない
        return const Text('Try restarting');
    }
  }
}
