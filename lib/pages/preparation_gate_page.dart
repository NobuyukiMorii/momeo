import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/platform/asset_pack_delivery.dart';
import 'package:momeo/providers/stt_providers.dart';
import 'package:momeo/stt/stt_transcriber.dart';
import 'package:momeo/widgets/intro_setting_layout.dart';
import 'package:momeo/widgets/phase_slide_text.dart';

// ---------------------------------
// 待ち画面が出し分ける5つのフェーズ（表示文言は _resolveStatus が決める）
// ---------------------------------
enum PreparationPhase {
  gettingReady,
  downloading,
  almostThere,
  retrying,
  tryRestarting,
}

// ---------------------------------
// PreparationGatePage — 文字化エンジンの準備が終わるまで受け止める待ち画面
// スプラッシュと同じ見た目（IntroSettingLayout ＋ スライドテキスト）に揃える。
// スライドの要否は PhaseSlideText 側の判断に任せ、ここではフェーズと文言だけ決める。
// ---------------------------------
class PreparationGatePage extends ConsumerWidget {
  const PreparationGatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engineState = ref.watch(sttEngineProvider);
    final downloadState = ref.watch(sttModelDownloadStateProvider);
    final restartSuggested = ref.watch(sttRestartSuggestedProvider);

    final (phase, text) =
        _resolveStatus(engineState, downloadState, restartSuggested);

    return Scaffold(
      body: IntroSettingLayout(
        title: DefaultTextStyle(
          style: AppTextStyles.headline.copyWith(color: AppColors.onSurface),
          child: PhaseSlideText(phase: phase, text: text),
        ),
      ),
    );
  }

  // ---------------------------------
  // エンジンの準備状態・DL状態から、出すべきフェーズと文言を決める
  // ---------------------------------
  (PreparationPhase, String) _resolveStatus(
    AsyncValue<SttTranscriber> engineState,
    AsyncValue<AssetPackState> downloadState,
    bool restartSuggested,
  ) {
    // ---------------------------------
    // エンジンが失敗し、次の自動再試行を待っている間 → 再試行中の表示
    //   連続失敗が閾値を超えていたら再起動の提案に切り替える（裏の再試行は続く）。
    //   再実行中（isLoading）は直前のエラーが保持されたままになるため除外し、
    //   DLが再開していれば下の Downloading 表示へ戻す
    // ---------------------------------
    if (engineState.hasError && !engineState.isLoading) {
      return restartSuggested
          ? (PreparationPhase.tryRestarting, 'Try restarting')
          : (PreparationPhase.retrying, 'Retrying');
    }

    // ---------------------------------
    // DL状態が未取得 → DLがまだ始まる前と同じ扱い
    // ---------------------------------
    final download = downloadState.value;
    if (download == null) {
      return (PreparationPhase.gettingReady, 'Getting ready');
    }

    // ---------------------------------
    // DL状態ごとに出し分ける
    //   completed には iOS のように自動DLが無い環境（常に完了扱い）も含まれる
    // ---------------------------------
    switch (download.phase) {
      case AssetPackPhase.notStarted:
        return (PreparationPhase.gettingReady, 'Getting ready');
      case AssetPackPhase.downloading:
        final percent = ((download.progress ?? 0.0) * 100).round();
        return (PreparationPhase.downloading, 'Downloading $percent%');
      case AssetPackPhase.completed:
        return (PreparationPhase.almostThere, 'Almost there');
      case AssetPackPhase.failed:
        // エンジン側の失敗確定を待つ間もフェーズを揺らさないよう、同じ判定で出す
        return restartSuggested
            ? (PreparationPhase.tryRestarting, 'Try restarting')
            : (PreparationPhase.retrying, 'Retrying');
    }
  }
}
