import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:momeo/foundation/app_colors.dart';
import 'package:momeo/foundation/app_spacing.dart';
import 'package:momeo/foundation/app_text_styles.dart';
import 'package:momeo/platform/os_transcriber_channel.dart';
import 'package:momeo/providers/stt_providers.dart';
import 'package:momeo/stt/stt_audio_worker.dart';
import 'package:momeo/widgets/activity_dots_text.dart';
import 'package:momeo/widgets/content_slide_switcher.dart';
import 'package:momeo/widgets/record_button_press.dart';

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
class PreparationGatePage extends ConsumerStatefulWidget {
  const PreparationGatePage({super.key});

  @override
  ConsumerState<PreparationGatePage> createState() =>
      _PreparationGatePageState();
}

class _PreparationGatePageState extends ConsumerState<PreparationGatePage> {
  // ダウンロードの進み具合を問い合わせる間隔
  static const _pollInterval = Duration(seconds: 1);

  // ダウンロード中だけ動かす、進み具合の問い合わせ
  Timer? _pollTimer;

  // ダウンロード中になってから、最初の問い合わせの答えが返ったか
  bool _hasReadProgress = false;

  // 直近に分かった進み具合（0.0〜1.0）。分からなければ null
  double? _downloadFraction;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------
  // ダウンロード中のフェーズの間だけ、進み具合を問い合わせ続ける
  // ---------------------------------
  void _updatePolling(PreparationPhase phase) {
    final isDownloading = phase == PreparationPhase.downloadingLanguage;

    if (isDownloading && _pollTimer == null) {
      _readProgress();
      _pollTimer = Timer.periodic(_pollInterval, (_) => _readProgress());
    }

    if (!isDownloading && _pollTimer != null) {
      _pollTimer!.cancel();
      _pollTimer = null;
      _hasReadProgress = false;
      _downloadFraction = null;
    }
  }

  Future<void> _readProgress() async {
    final fraction = await OsTranscriberChannel.downloadProgress();
    if (!mounted || _pollTimer == null) return;
    setState(() {
      _hasReadProgress = true;
      _downloadFraction = fraction;
    });
  }

  @override
  Widget build(BuildContext context) {
    final engineState = ref.watch(sttEngineProvider);
    final restartSuggested = ref.watch(sttRestartSuggestedProvider);

    final phase = _resolvePhase(engineState, restartSuggested);
    _updatePolling(phase);

    // 進み具合が分かるときだけ、外側の輪をその割合だけ伸ばす（分からなければ一周の輪のまま）
    final ringProgress = phase == PreparationPhase.downloadingLanguage
        ? _downloadFraction
        : null;

    // ---------------------------------
    // スプラッシュから続けて、画面中央に録音ボタンを止めたまま出し、その下にいまの状況を出す
    // 上にも状況欄と同じ高さの見えない余白を置き、ボタンが画面のちょうど中央に来るようにする
    // ---------------------------------
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: _statusAreaHeight + AppSpacing.xl),
            RecordButtonPress(playsPress: false, ringProgress: ringProgress),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              height: _statusAreaHeight,
              child: DefaultTextStyle(
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.onSurface,
                ),
                textAlign: TextAlign.center,
                child: ContentSlideSwitcher(
                  contentKey: phase,
                  child: SizedBox(
                    width: double.infinity,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _buildPhaseContent(phase),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 録音ボタンの下の、状況を出す欄の高さ（2行まで入る）
  static const _statusAreaHeight = 40.0;

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
        // 読み込み中は録音ボタンだけを出し、文字は出さない
        return const SizedBox.shrink();
      case PreparationPhase.retrying:
        return const ActivityDotsText('Retrying');
      case PreparationPhase.tryRestarting:
        // 「処理中」ではなくユーザーへの依頼なので、動きは付けない
        return const Text('Please restart the app');
      case PreparationPhase.unsupported:
        // 再起動しても変わらないお知らせなので、動きは付けない
        return const Text('Not available on this device');
      case PreparationPhase.downloadingLanguage:
        return _buildDownloadingText();
    }
  }

  // ---------------------------------
  // 言語のモデルのダウンロード中の文言
  //   進み具合が分かるときは輪が伸びるので文言だけ、分からないときは文言の後ろでドットを動かす
  //   最初の問い合わせの答えが返るまでの一瞬も文言だけにする（進み具合が取れる端末でドットを一瞬見せないため）
  // ---------------------------------
  Widget _buildDownloadingText() {
    const label = 'Downloading the language model';

    if (_hasReadProgress && _downloadFraction == null) {
      return const ActivityDotsText(label);
    }

    // ドットの分の幅は透明で取っておき、ドットに切り替わっても文言の位置が動かないようにする
    return const Text.rich(
      TextSpan(
        text: label,
        children: [
          TextSpan(
            text: ' ...',
            style: TextStyle(color: Colors.transparent),
          ),
        ],
      ),
    );
  }
}
