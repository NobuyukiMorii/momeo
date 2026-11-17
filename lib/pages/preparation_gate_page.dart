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
// 待ち画面の6フェーズ
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

  /// 言語のモデルが入り、準備ができた。録音ボタンをもう一度押してから次の画面へ進む
  downloadFinished,
}

// ---------------------------------
// 文字化エンジンの準備が終わるまでの待ち画面
// ---------------------------------
// 準備ができたら、ふつうは呼び出し元がすぐ次の画面に切り替える。
// ダウンロードを待っていたときだけ、呼び出し元は待ち画面を残し、
// 待ち画面は録音ボタンを押す動きを見せてから onFinished で知らせる
class PreparationGatePage extends ConsumerStatefulWidget {
  const PreparationGatePage({super.key, this.onFinished});

  // ダウンロードを待ったあと、録音ボタンを押す動きが終わったときに呼ばれる
  final VoidCallback? onFinished;

  @override
  ConsumerState<PreparationGatePage> createState() =>
      _PreparationGatePageState();
}

class _PreparationGatePageState extends ConsumerState<PreparationGatePage> {
  // ダウンロードの進み具合を問い合わせる間隔
  static const _pollInterval = Duration(seconds: 1);

  // 押す動きが終わってから次の画面へ進むまでの間（押し終わった姿を少し見せるため）
  static const _afterPressPause = Duration(milliseconds: 300);

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
  //   ダウンロードが終わったときは、輪を 100% にするか一周のままにするかを決めるため、直近の進み具合を残す
  void _updatePolling(PreparationPhase phase) {
    final isDownloading = phase == PreparationPhase.downloadingLanguage;

    if (isDownloading && _pollTimer == null) {
      _readProgress();
      _pollTimer = Timer.periodic(_pollInterval, (_) => _readProgress());
    }

    if (!isDownloading && _pollTimer != null) {
      _pollTimer!.cancel();
      _pollTimer = null;
      if (phase != PreparationPhase.downloadFinished) {
        _hasReadProgress = false;
        _downloadFraction = null;
      }
    }
  }

  // ダウンロードが終わったあと、録音ボタンが押され始めたか（文言を消すきっかけ）
  bool _hasPressStarted = false;

  // 押され始めたら、黒丸の中の数字と同じときに、録音ボタンの下の文言も消す
  void _onPressStarted() {
    setState(() => _hasPressStarted = true);
  }

  // 押す動きが終わったら、少し間を置いて次の画面へ進む
  Future<void> _finishAfterPress() async {
    await Future<void>.delayed(_afterPressPause);
    if (!mounted) return;
    widget.onFinished?.call();
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
    // ダウンロードが終わったら、進み具合を出していたときだけ 100% まで伸ばしきる
    final double? ringProgress;
    switch (phase) {
      case PreparationPhase.downloadingLanguage:
        ringProgress = _downloadFraction;
      case PreparationPhase.downloadFinished:
        ringProgress = _downloadFraction == null ? null : 1.0;
      default:
        ringProgress = null;
    }

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
            RecordButtonPress(
              playsPress: phase == PreparationPhase.downloadFinished,
              ringProgress: ringProgress,
              onPressStarted: _onPressStarted,
              onPressFinished: _finishAfterPress,
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              height: _statusAreaHeight,
              child: _buildStatusArea(phase),
            ),
          ],
        ),
      ),
    );
  }

  // 録音ボタンの下の、状況を出す欄の高さ（button の大きさで2行まで入る）
  static const _statusAreaHeight = 40.0;

  // ---------------------------------
  // 録音ボタンの下の状況欄
  //   ダウンロードが終わっても、押され始めるまではダウンロード中の文言をそのまま出し（スライドさせない）、
  //   押され始めたら、黒丸の中の数字と同じときに動きを付けずに消す
  // ---------------------------------
  Widget _buildStatusArea(PreparationPhase phase) {
    if (_hasPressStarted) return const SizedBox.shrink();

    final shownPhase = phase == PreparationPhase.downloadFinished
        ? PreparationPhase.downloadingLanguage
        : phase;

    return DefaultTextStyle(
      style: AppTextStyles.button.copyWith(color: AppColors.onSurface),
      textAlign: TextAlign.center,
      child: ContentSlideSwitcher(
        contentKey: shownPhase,
        child: SizedBox(
          width: double.infinity,
          child: Align(
            alignment: Alignment.topCenter,
            child: _buildPhaseContent(shownPhase),
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
    // 準備ができた（この画面が出たままなのは、ダウンロードを待っていたときだけ）
    // ---------------------------------
    if (engineState.hasValue && !engineState.isLoading) {
      return PreparationPhase.downloadFinished;
    }

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
      case PreparationPhase.downloadFinished:
        // 状況欄はダウンロード中の文言を出し続けてから消すので、ふつうはここに来ない
        return const SizedBox.shrink();
    }
  }

  // ---------------------------------
  // ダウンロード中の文言（ユーザーには何をダウンロードしているかは関係ないので、ただ Downloading とだけ出す）
  //   進み具合が分かるときは輪が伸びるので文言だけ、分からないときは文言の後ろでドットを動かす
  //   最初の問い合わせの答えが返るまでの一瞬も文言だけにする（進み具合が取れる端末でドットを一瞬見せないため）
  // ---------------------------------
  Widget _buildDownloadingText() {
    const label = 'Downloading';

    if (_hasReadProgress && _downloadFraction == null) {
      return const ActivityDotsText(label);
    }

    // ドットの分の幅は前後とも透明で取っておき、ドットに切り替わっても文言の位置が動かないようにする（ActivityDotsText と同じ幅）
    return const Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '... ',
            style: TextStyle(color: Colors.transparent),
          ),
          TextSpan(text: label),
          TextSpan(
            text: ' ...',
            style: TextStyle(color: Colors.transparent),
          ),
        ],
      ),
    );
  }
}
