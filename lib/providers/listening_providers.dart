import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:momeo/database/app_database.dart';
import 'package:momeo/providers/database_providers.dart';
import 'package:momeo/providers/settings_providers.dart';
import 'package:momeo/providers/stt_providers.dart';
import 'package:momeo/repositories/voice_memo_repository.dart';
import 'package:momeo/stt/listening_background_notice.dart';
import 'package:momeo/stt/listening_foreground_service.dart';
import 'package:momeo/stt/stt_listening_pipeline.dart';
import 'package:momeo/stt/stt_model_provisioner.dart';

// ============================================================
// listeningProvider — リスニング画面の状態を一元管理する
//
//   ページ（listening_page）は watch して描画し、状態の変化を
//   アクティブカードのアニメーションに翻訳するだけの View に徹する。
//   録音パイプラインの生成・開始・破棄もこの Notifier が持つ。
//
//   autoDispose: 画面が watch をやめる（＝画面を離れる）と Notifier ごと
//   破棄され、パイプラインも止まる。破棄時に flush された末尾の発話も
//   DB への保存だけは行う（state には触れない）。
// ============================================================

final listeningProvider =
    AsyncNotifierProvider.autoDispose<ListeningNotifier, ListeningState>(
  ListeningNotifier.new,
);

// ---------------------------------
// ListeningState — リスニング画面の状態（イミュータブル）
// ---------------------------------
class ListeningState {
  const ListeningState({
    this.memos = const [],
    this.speechActive = false,
    this.typeInMemoId,
    this.emptyResultCount = 0,
  });

  // 確定済みメモ一覧（新しい順）
  final List<VoiceMemo> memos;

  // 今ユーザーが発話中か（VAD の判定）
  final bool speechActive;

  // タイピング演出を付けるメモの id（直前に確定した1件。見せ切ったら null に戻る）
  final int? typeInMemoId;

  // 空の認識結果（咳・物音の誤検知）で終わった回数の通し番号。
  // ページはこの増加を「アクティブカードをスライドアウトさせる合図」として使う
  final int emptyResultCount;

  // ---------------------------------
  // 状態遷移（意図が分かる名前の生成メソッドで揃える）
  // ---------------------------------

  // 発話中かどうかが変わった
  ListeningState withSpeechActive(bool isActive) {
    return ListeningState(
      memos: memos,
      speechActive: isActive,
      typeInMemoId: typeInMemoId,
      emptyResultCount: emptyResultCount,
    );
  }

  // メモが1件確定した（先頭に差し、タイピング演出の対象にする）
  ListeningState withMemoAdded(VoiceMemo memo) {
    return ListeningState(
      memos: [memo, ...memos],
      speechActive: speechActive,
      typeInMemoId: memo.id,
      emptyResultCount: emptyResultCount,
    );
  }

  // 空の認識結果で発話が終わった
  ListeningState withEmptyResult() {
    return ListeningState(
      memos: memos,
      speechActive: speechActive,
      typeInMemoId: typeInMemoId,
      emptyResultCount: emptyResultCount + 1,
    );
  }

  // メモの削除
  ListeningState withMemosRemoved(Set<int> removedIds) {
    return ListeningState(
      memos: [
        for (final memo in memos)
          if (!removedIds.contains(memo.id)) memo,
      ],
      speechActive: speechActive,
      // 演出の対象が消えていたら、対象ごと下ろす
      typeInMemoId: removedIds.contains(typeInMemoId) ? null : typeInMemoId,
      emptyResultCount: emptyResultCount,
    );
  }

  // タイピング演出を使い切った
  ListeningState withTypeInConsumed() {
    return ListeningState(
      memos: memos,
      speechActive: speechActive,
      typeInMemoId: null,
      emptyResultCount: emptyResultCount,
    );
  }
}

// ---------------------------------
// ListeningNotifier — 状態遷移とパイプラインの所有
// ---------------------------------
class ListeningNotifier extends AsyncNotifier<ListeningState> {
  late VoiceMemoRepository _repository;
  SttListeningPipeline? _pipeline;

  // 直近のマイク音量（0.0〜1.0）。音量メーターが毎フレーム読みに行く。
  // チャンク頻度で飛んでくるため state には載せず、ただのフィールド保持にする。
  double _latestLevel = 0;
  double get latestLevel => _latestLevel;

  // 破棄後は state に触れないためのフラグ（DB への保存だけは続ける）
  bool _disposed = false;

  // 背面でも録音を続ける態勢が成立しているか
  // （設定 ON かつ通知許可あり。Android はさらに常駐サービスの起動まで）
  bool _keepsRecordingInBackground = false;

  @override
  Future<ListeningState> build() async {
    _repository = ref.watch(voiceMemoRepositoryProvider);
    _disposed = false;

    // 背面遷移で録音を止め、前面復帰で再開する（inactive では何もしない）
    final lifecycleListener = AppLifecycleListener(
      onPause: _onAppPaused,
      onResume: _onAppResumed,
    );

    // 録音中に設定を切り替えられたら、その場で背面録音の態勢へ反映する
    ref.listen(backgroundRecordingProvider, _onBackgroundRecordingSettingChanged);

    // 常駐通知の停止ボタンからの停止要求を受け取る（Android）
    FlutterForegroundTask.addTaskDataCallback(_onServiceDataReceived);

    ref.onDispose(() {
      _disposed = true;
      lifecycleListener.dispose();
      FlutterForegroundTask.removeTaskDataCallback(_onServiceDataReceived);
      _pipeline?.dispose();
      _pipeline = null;
      // 画面を離れたら常駐サービスも畳む（通知を出しっぱなしにしない）
      unawaited(ListeningForegroundService.stop());
    });

    final memos = await _repository.findAll();

    // パイプラインの起動は待たず、メモ一覧を先に表示できるようにする
    // （準備ゲートを通ってこの画面に来るため、エンジンは通常すぐ手に入る）
    unawaited(_startPipeline());

    return ListeningState(memos: memos);
  }

  // ---------------------------------
  // 録音 → 区切り → 文字化パイプラインの起動
  // ---------------------------------
  Future<void> _startPipeline() async {
    try {
      // 全画面で共有しているSTTエンジンを受け取る（ここでは新規作成しない）
      final transcriber = await ref.read(sttEngineProvider.future);
      // VADモデル（silero）のパスを取得する
      final sileroPath = await SttModelProvisioner().ensureSilero();
      if (_disposed) return;

      final pipeline = SttListeningPipeline(
        transcriber: transcriber,
        sileroPath: sileroPath,
        onText: _onText,
        onSpeechActiveChanged: _onSpeechActiveChanged,
        onLevelChanged: (level) => _latestLevel = level,
      );

      // 設定 ON なら、録音を始める前に背面でも続ける態勢を作る
      // （Android はサービスが先でないと、背面遷移でマイクを切られる）
      _keepsRecordingInBackground = await _prepareBackgroundRecording();

      await pipeline.start();

      if (_disposed) {
        await pipeline.dispose();
        return;
      }
      _pipeline = pipeline;

      // 起動処理の間に背面へ回られていたら、起動直後に止めて整合させる
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
        await pipeline.stop();
      }
    } catch (error) {
      // 準備待ち画面やエラー表示はまだ無い。ここではログに記録するだけ
      debugPrint('[listening] リスニングを開始できませんでした: $error');
    }
  }

  // ---------------------------------
  // 背面でも録音を続ける態勢を作る（成立したかを返す）
  //   設定 OFF なら何もしない。ON でも通知許可が無ければ成立させない
  //   （通知の出ない背面録音を作らない → notes/background_recording/android.md）
  // ---------------------------------
  Future<bool> _prepareBackgroundRecording() async {
    // 設定を読む（読み込みが済んでいなければ無効扱い）
    final isEnabled =
        ref.read(backgroundRecordingProvider).value?.isEnabled ?? false;
    if (!isEnabled) return false;

    // 通知許可は OS 設定から後で取り消せるため、開始のたびに確認する
    if (!await Permission.notification.isGranted) return false;

    // Android は microphone 型の常駐サービスが起動できて初めて成立する。
    // iOS は UIBackgroundModes の宣言が効くため、ここでは何も起動しない
    if (Platform.isAndroid) {
      return ListeningForegroundService.start();
    }
    return true;
  }

  // ---------------------------------
  // 録音中に設定を切り替えられたときの反映
  // ---------------------------------
  Future<void> _onBackgroundRecordingSettingChanged(
    AsyncValue<BackgroundRecordingState>? previous,
    AsyncValue<BackgroundRecordingState> next,
  ) async {
    final wasEnabled = previous?.value?.isEnabled ?? false;
    final isEnabled = next.value?.isEnabled ?? false;
    if (isEnabled == wasEnabled) return;
    if (_pipeline == null) return;

    if (isEnabled) {
      _keepsRecordingInBackground = await _prepareBackgroundRecording();
    } else {
      _keepsRecordingInBackground = false;
      await ListeningForegroundService.stop();
    }
  }

  // ---------------------------------
  // 常駐通知の停止ボタンが押されたとき（Android）
  //   録音を止め、設定も OFF に戻す（通知からの停止 = 同意の撤回として扱う）
  // ---------------------------------
  void _onServiceDataReceived(Object data) {
    if (data != listeningServiceStopRequested) return;
    _keepsRecordingInBackground = false;
    unawaited(_pipeline?.stop());
    unawaited(ListeningForegroundService.stop());
    unawaited(ref.read(backgroundRecordingProvider.notifier).setEnabled(false));
  }

  // ---------------------------------
  // アプリのライフサイクルに合わせた停止・再開
  //   判定は paused / resumed だけ。inactive はコントロールセンターを
  //   引き出しただけでも起きるため、反応しない
  // ---------------------------------
  void _onAppPaused() {
    // 背面でも録音を続ける態勢なら止めない。iOS はローカル通知で録音中を示す
    if (_keepsRecordingInBackground) {
      debugPrint('[listening] 背面遷移: 背面でも録音を続けます');
      unawaited(ListeningBackgroundNotice.show());
      return;
    }
    // stop() 内の flush が、背面に入る直前の発話を確定・保存する
    debugPrint('[listening] 背面遷移: 録音を停止します');
    unawaited(_pipeline?.stop());
  }

  Future<void> _onAppResumed() async {
    debugPrint('[listening] 前面復帰: 録音を再開します');
    // 背面中に出した「録音中」のローカル通知を消す（iOS）
    unawaited(ListeningBackgroundNotice.dismiss());
    try {
      await _pipeline?.start();
    } catch (error) {
      // 背面中の権限取り消しなどはログのみ。権限の取り直しは RootView が担う
      debugPrint('[listening] リスニングを再開できませんでした: $error');
    }
  }

  // VAD の発話開始・終了の通知を状態へ写す
  void _onSpeechActiveChanged(bool isActive) {
    if (_disposed) return;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.withSpeechActive(isActive));
  }

  // ---------------------------------
  // 1発話の確定テキストの受け取り
  //   空: 誤検知として通し番号だけ進める（ページが退場の合図に使う）
  //   あり: DB へ保存して先頭に差し、タイピング演出の対象にする
  //   ※ 画面を離れた後に届く末尾の発話も、DB への保存だけは行う
  // ---------------------------------
  Future<void> _onText(String text) async {
    final content = text.trim();

    if (content.isEmpty) {
      if (_disposed) return;
      final current = state.value;
      if (current == null) return;
      state = AsyncData(current.withEmptyResult());
      return;
    }

    final createdAt = DateTime.now();
    final id = await _repository.insert(content: content, createdAt: createdAt);

    if (_disposed) return;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.withMemoAdded(
      VoiceMemo(id: id, content: content, createdAt: createdAt),
    ));
  }

  // ---------------------------------
  // 選択中のメモを DB ごと削除する（元に戻す手段は持たない）
  // ---------------------------------
  Future<void> deleteMemos(Set<int> memoIds) async {
    if (memoIds.isEmpty) return;
    await _repository.deleteByIds(memoIds.toList());

    if (_disposed) return;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.withMemosRemoved(memoIds));
  }

  // タイピング演出を使い切ったときにページから呼ばれる（再表示時の再再生を防ぐ）
  void onTypingComplete(int memoId) {
    if (_disposed) return;
    final current = state.value;
    if (current == null || current.typeInMemoId != memoId) return;
    state = AsyncData(current.withTypeInConsumed());
  }
}
