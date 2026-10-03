import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
// アプリがバックグラウンドかフォアグラウンドかを把握するための3つのクラスを取り込む
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:flutter_foreground_task/flutter_foreground_task.dart'
    show FlutterForegroundTask;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:momeo/database/app_database.dart';
import 'package:momeo/providers/database_providers.dart';
import 'package:momeo/providers/settings_providers.dart';
import 'package:momeo/providers/stt_providers.dart';
import 'package:momeo/repositories/voice_memo_repository.dart';
import 'package:momeo/stt/listening_foreground_service.dart';
import 'package:momeo/stt/listening_live_activity.dart';
import 'package:momeo/stt/stt_audio_worker.dart';
import 'package:momeo/stt/stt_listening_pipeline.dart';
import 'package:momeo/stt/stt_model_provisioner.dart';

// ============================================================
// listeningProvider — リスニング画面の状態を一元管理する
//
//   ページ（listening_page）は watch して描画するだけの View に徹する。
//   録音パイプラインの生成・開始・破棄もこの Notifier が持つ。
//
//   autoDispose: 画面が watch をやめる（＝画面を離れる）と Notifier ごと
//   破棄され、パイプラインも止まる。破棄時に flush された末尾の発話も
//   DB への保存だけは行う（state には触れない）。
// ============================================================

// 今のブロックへの追記を終了するまでの、発話が途切れている時間
const _appendIdleLimit = Duration(seconds: 10);

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
    this.awaitingTranscription = false,
    this.appendTargetId,
    this.typeInMemoId,
    this.typeInFrom = 0,
  });

  // 確定済みメモ一覧（新しい順）
  final List<VoiceMemo> memos;

  // 今ユーザーが発話中か（VAD の判定）
  final bool speechActive;

  // 発話が終わり、文字化の結果（空の結果も含む）を待っているか
  final bool awaitingTranscription;

  // 次の発話を書き足すメモの id
  final int? appendTargetId;

  // タイピング演出を付けるメモの id（直前に確定した1件。見せ切ったら null に戻る）
  final int? typeInMemoId;

  // タイピング演出を始める文字数
  final int typeInFrom;

  // ---------------------------------
  // 状態遷移（意図が分かる名前の生成メソッドで揃える）
  // ---------------------------------

  // 発話中かどうかが変わった
  ListeningState withSpeechActive(bool isActive) {
    return ListeningState(
      memos: memos,
      speechActive: isActive,
      // 発話が終わったら、結果が届くまで待ちに入る
      awaitingTranscription:
          awaitingTranscription || (speechActive && !isActive),
      appendTargetId: appendTargetId,
      typeInMemoId: typeInMemoId,
      typeInFrom: typeInFrom,
    );
  }

  // メモが1件確定した（先頭に差し、タイピング演出の対象にする）。
  // このメモを次の追記先にする
  ListeningState withMemoAdded(VoiceMemo memo) {
    return ListeningState(
      memos: [memo, ...memos],
      speechActive: speechActive,
      awaitingTranscription: false,
      appendTargetId: memo.id,
      typeInMemoId: memo.id,
      typeInFrom: 0,
    );
  }

  // 追記先の末尾に書き足した（先頭を差し替え、書き足した分だけを打ち出す）
  ListeningState withMemoAppended(VoiceMemo memo, {required int typeInFrom}) {
    return ListeningState(
      memos: [memo, ...memos.skip(1)],
      speechActive: speechActive,
      awaitingTranscription: false,
      appendTargetId: memo.id,
      typeInMemoId: memo.id,
      typeInFrom: typeInFrom,
    );
  }

  // 今のブロックへの追記を終了した（次の発話は新しいブロックになる）
  ListeningState withCurrentBlockEnded() {
    return ListeningState(
      memos: memos,
      speechActive: speechActive,
      awaitingTranscription: awaitingTranscription,
      appendTargetId: null,
      typeInMemoId: typeInMemoId,
      typeInFrom: typeInFrom,
    );
  }

  // 空の認識結果（咳・物音の誤検知）で発話が終わった
  ListeningState withEmptyResult() {
    return ListeningState(
      memos: memos,
      speechActive: speechActive,
      awaitingTranscription: false,
      appendTargetId: appendTargetId,
      typeInMemoId: typeInMemoId,
      typeInFrom: typeInFrom,
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
      awaitingTranscription: awaitingTranscription,
      // 追記先が消えていたら、追記先も手放す
      appendTargetId: removedIds.contains(appendTargetId) ? null : appendTargetId,
      // 演出の対象が消えていたら、対象ごと下ろす
      typeInMemoId: removedIds.contains(typeInMemoId) ? null : typeInMemoId,
      typeInFrom: typeInFrom,
    );
  }

  // タイピング演出を使い切った
  ListeningState withTypeInConsumed() {
    return ListeningState(
      memos: memos,
      speechActive: speechActive,
      awaitingTranscription: awaitingTranscription,
      appendTargetId: appendTargetId,
      typeInMemoId: null,
      typeInFrom: typeInFrom,
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

  // 直近の発話が始まった時刻の一時的な記録
  DateTime? _speechStartedAt;

  // 次の発話の追記先
  VoiceMemo? _appendTarget;

  // 追記先へ最後に書き足した時刻
  DateTime? _lastAppendedAt;

  // 破棄後は state に触れないためのフラグ（DB への保存だけは続ける）
  bool _disposed = false;

  // バックグラウンドでも録音を続ける状態が成立しているか ↓
  // ・ 「バックグラウンド録音」設定が ON
  // ・ （Androidの場合） フォアグラウンドサービスが起動できている
  // ・ （iOSの場合） 「バックグラウンド録音」設定が ON なだけで成立
  bool _keepsRecordingInBackground = false;

  @override
  Future<ListeningState> build() async {
    _repository = ref.watch(voiceMemoRepositoryProvider);
    _disposed = false;

    // アプリのライフサイクルに合わせた録音の停止・再開を管理するリスナーを作成
    final lifecycleListener = AppLifecycleListener(
      onPause: _onAppPaused, // バックグラウンド遷移で録音を止める
      onResume: _onAppResumed, // フォアグラウンド復帰で再開する
    );

    // 録音中に「バックグラウンド録音」設定を切り替えられたら、その場で反映する
    ref.listen(backgroundRecordingProvider, _onBackgroundRecordingSettingChanged);

    // 常駐通知の停止ボタンからの停止要求を受け取る（Android）
    FlutterForegroundTask.addTaskDataCallback(_onServiceDataReceived);

    ref.onDispose(() {
      _disposed = true;
      lifecycleListener.dispose();
      FlutterForegroundTask.removeTaskDataCallback(_onServiceDataReceived);
      _pipeline?.dispose();
      _pipeline = null;
      unawaited(ListeningForegroundService.stop()); // フォアグラウンドサービスを終了
      unawaited(ListeningLiveActivity.dismiss()); // 「録音中」の Live Activity を消す（iOS）
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
      // 全画面で共有している音声 isolate を受け取る（ここでは新規作成しない）
      final worker = await ref.read(sttEngineProvider.future);
      // VADモデル（silero）のパスを取得する
      final sileroPath = await SttModelProvisioner().ensureSilero();
      if (_disposed) return;

      final pipeline = SttListeningPipeline(
        worker: worker,
        sileroPath: sileroPath,
        onTranscribed: _onTranscribed,
        onSpeechActiveChanged: _onSpeechActiveChanged,
        onLevelChanged: (level) => _latestLevel = level,
      );

      // 録音を始める前にバックグラウンドでも続ける状態を作る
      _keepsRecordingInBackground = await _prepareBackgroundRecording();

      // iOS の Live Activity を表示
      if (_keepsRecordingInBackground) {
        unawaited(ListeningLiveActivity.show());
      }

      await pipeline.start();

      if (_disposed) {
        await pipeline.dispose();
        await ListeningForegroundService.stop();
        await ListeningLiveActivity.dismiss();
        return;
      }
      _pipeline = pipeline;

      // _startPipeline() の最中にアプリがバックグラウンドへ移ると、_onAppPaused の時点で録音がまだ無い。
      // その場合の保険として、今バックグラウンドにいるなら始まったばかりの録音をここで止める
      if (!_keepsRecordingInBackground && // バックグラウンドで録音を続ける状態が成立していない
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) { // アプリがバックグラウンドに移った
        await pipeline.stop();
      }
    } catch (error) {
      // 準備待ち画面やエラー表示はまだ無い。ここではログに記録するだけ
      debugPrint('[listening] リスニングを開始できませんでした: $error');
    }
  }

  // ---------------------------------
  // バックグラウンドでも録音を続けられるよう準備
  // ---------------------------------
  Future<bool> _prepareBackgroundRecording() async {
    // 「バックグラウンド録音」設定を取得
    final isEnabled =
        ref.read(backgroundRecordingProvider).value?.isEnabled ?? false;
    // 「バックグラウンド録音」設定が OFF なら何もしない
    if (!isEnabled) return false;
    // Android はフォアグラウンドサービスまで起動できて初めて成立する
    if (Platform.isAndroid) {
      return ListeningForegroundService.start();
    }
    // iOS は Info.plist の宣言（UIBackgroundModes の audio）が効くため、ここで起動するものは無い
    return true;
  }

  // ---------------------------------
  // 「バックグラウンド録音」設定を切り替えた時
  // ---------------------------------
  Future<void> _onBackgroundRecordingSettingChanged(
    AsyncValue<BackgroundRecordingState>? previous,
    AsyncValue<BackgroundRecordingState> next,
  ) async {
    // 「バックグラウンド録音」の前の設定
    final wasEnabled = previous?.value?.isEnabled ?? false;
    // 「バックグラウンド録音」の新しい設定
    final isEnabled = next.value?.isEnabled ?? false;
    // 前の設定と新しい設定が同じなら何もしない
    if (isEnabled == wasEnabled) return;
    // 録音中でなければ何もしない
    if (_pipeline == null) return;

    // 「バックグラウンド録音」設定が ON なら
    if (isEnabled) {
      // フォアグラウンドサービスを起動
      _keepsRecordingInBackground = await _prepareBackgroundRecording();
      // iOS の Live Activity を表示
      if (_keepsRecordingInBackground) {
        unawaited(ListeningLiveActivity.show());
      }
    } else { // 「バックグラウンド録音」設定が OFF なら
      // フォアグラウンドサービスを終了
      _keepsRecordingInBackground = false;
      await ListeningForegroundService.stop();
      // iOS の Live Activity を消す
      await ListeningLiveActivity.dismiss();
    }
  }

  // ---------------------------------
  // 常駐通知の停止ボタンが押されたとき（Android）
  // ---------------------------------
  void _onServiceDataReceived(Object data) {
    // 停止要求以外のメッセージは無視
    if (data != listeningServiceStopRequested) return;
    // バックグラウンドでも録音を続ける状態を解除
    _keepsRecordingInBackground = false;
    // フォアグラウンドサービスを終了
    unawaited(ListeningForegroundService.stop());
    // 「バックグラウンド録音」設定を OFF に戻す
    unawaited(ref.read(backgroundRecordingProvider.notifier).setEnabled(false));
    // バックグラウンドにいるとき
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
      // 録音を停止
      debugPrint('[listening] 通知の停止ボタン: 録音を停止します');
      unawaited(_stopRecordingAndEndBlock());
    }
  }

  // ---------------------------------
  // アプリがバックグラウンドに移ったときの録音の停止・継続
  // ---------------------------------
  void _onAppPaused() {
    if (_keepsRecordingInBackground) { // バックグラウンドでも録音を続けられる状態なら
      // 録音を止めずにそのまま続ける（追記先もそのまま保つ）
      debugPrint('[listening] バックグラウンド遷移: 録音を続けます');
      return;
    }
    debugPrint('[listening] バックグラウンド遷移: 録音を停止します');
    unawaited(_stopRecordingAndEndBlock());
  }

  // ---------------------------------
  // 録音を止め、新しいブロックで次の発話を始める
  // ---------------------------------
  Future<void> _stopRecordingAndEndBlock() async {
    // 録音を停止
    await _pipeline?.stop();
    // 今のブロックを終わりにする（次の発話は新しいブロックになる）
    _endCurrentBlock();
  }

  // ---------------------------------
  // アプリがフォアグラウンドに復帰したときの録音の再開
  //   バックグラウンドの間に録音が黙って止まっていることがあるため、
  //   止めていた場合の再開と、続けていた場合の生死の確認を ensureRunning にまとめる
  // ---------------------------------
  Future<void> _onAppResumed() async {
    debugPrint('[listening] フォアグラウンド復帰: 録音を再開します');
    // バックグラウンドでも録音を続ける状態なら、iOS の Live Activity が消えていないか確認して出し直す
    if (_keepsRecordingInBackground) {
      unawaited(ListeningLiveActivity.show());
    }
    try {
      await _pipeline?.ensureRunning();
    } catch (error) {
      // バックグラウンド中の権限取り消しなどはログのみ。権限の取り直しは RootView が担う
      debugPrint('[listening] リスニングを再開できませんでした: $error');
    }
  }

  // VAD の発話開始・終了の通知を状態へ写す
  void _onSpeechActiveChanged(bool isActive) {
    // 発話が始まった
    if (isActive) {
      _speechStartedAt = DateTime.now(); // 開始時刻を記録
      if (_shouldEndCurrentBlock()) {
        _endCurrentBlock(); // 今のブロックへの追記を終了（次の発話は新しいブロックになる）
      }
    }

    if (_disposed) return;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.withSpeechActive(isActive));
  }

  // ---------------------------------
  // 今のブロックへの追記を終了すべきか
  // ---------------------------------
  bool _shouldEndCurrentBlock() {

    // 今の追記先
    final appendTarget = _appendTarget;

    // 追記先が無ければ、追記続行
    if (appendTarget == null) return false;

    // 最後に書き足した時刻
    final lastAppendedAt = _lastAppendedAt;

    // 書き足した記録が無ければ判断できないので、終了（新ブロック追加）
    if (lastAppendedAt == null) return true;

    // 現在時刻
    final now = DateTime.now();

    // 最後のメモから基準となる時間が経過したら新ブロック追加 or 経過していなければ追記
    return now.difference(lastAppendedAt) >= _appendIdleLimit;
  }

  // ---------------------------------
  // 今のブロックへの追記を終了
  // ---------------------------------
  void _endCurrentBlock() {
    // 追記先を削除
    _appendTarget = null;
    // 最後に書き足した時刻を削除
    _lastAppendedAt = null;
    // 画面を離れた後は state に触れない
    if (_disposed) return;
    // 今の状態
    final current = state.value;
    // 読み込み中でまだ状態が無ければ、表示の更新はしない
    if (current == null) return;
    // 追記先が無くなったことを画面へ伝える（次の発話は新しいブロックになる）
    state = AsyncData(current.withCurrentBlockEnded());
  }

  // ---------------------------------
  // 1発話の確定テキストの受け取り
  //   空: 誤検知として結果待ちだけを解く。
  //       追記先には触れず、終了までの起点も動かさない
  //   あり: 追記先があればその末尾へ書き足し、無ければ新しく起こす
  //   ※ 画面を離れた後に届く末尾の発話も、DB への保存だけは行う
  // ---------------------------------
  Future<void> _onTranscribed(SttTranscribed result) async {
    final content = result.text.trim();

    if (content.isEmpty) {
      if (_disposed) return;
      final current = state.value;
      if (current == null) return;
      state = AsyncData(current.withEmptyResult());
      return;
    }
    final appendTarget = _appendTarget; // 今の追記先
    if (appendTarget == null) { // 追記先が無い
      await _startNewMemo(content); // 新しいブロックを作成
    } else { // 追記先がある
      await _appendToTarget(appendTarget, content); // そのブロックの末尾に追記
    }

    // 次の発話を同じブロックに入れるかどうかの起点にする
    _lastAppendedAt = DateTime.now();
  }

  // ---------------------------------
  // 新しいブロックを起こす（以後の発話は、このブロックへ追記していく）
  // ---------------------------------
  Future<void> _startNewMemo(String content) async {
    final createdAt = _speechStartedAt ?? DateTime.now();
    final id = await _repository.insert(content: content, createdAt: createdAt);
    final memo = VoiceMemo(id: id, content: content, createdAt: createdAt);
    // 次の追記先にする
    _appendTarget = memo;

    // ブロックが1つ増えたので、iOS の Live Activity の件数を進める（表示していなければ何もしない）
    unawaited(ListeningLiveActivity.incrementMemoCount());

    if (_disposed) return;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.withMemoAdded(memo));
  }

  // ---------------------------------
  // ブロックの末尾に追記
  // ---------------------------------
  Future<void> _appendToTarget(VoiceMemo appendTarget, String content) async {
    // 発話と発話の間は区切らず、そのままつなげる
    final appended = '${appendTarget.content}$content';
    // 追記先の内容を更新
    await _repository.updateContent(id: appendTarget.id, content: appended);
    // state 用にメモを作り直す
    final memo = VoiceMemo(
      id: appendTarget.id,
      content: appended,
      createdAt: appendTarget.createdAt,
    );
    // 次の追記先として持ち直す
    _appendTarget = memo;

    // 画面を離れた後は state に触れない（DB への保存はここまでで済んでいる）
    if (_disposed) return;
    // 今の状態
    final current = state.value;
    // 読み込み中でまだ状態が無ければ、表示の更新はしない
    if (current == null) return;
    // 最新のメモを、書き足した後の内容に差し替える
    state = AsyncData(current.withMemoAppended(
      memo,
      // 新しく足した分だけ1文字ずつ表示する（前からある本文はそのまま）
      typeInFrom: appended.length - content.length,
    ));
  }

  // ---------------------------------
  // 選択中のメモを DB ごと削除する（元に戻す手段は持たない）
  // ---------------------------------
  Future<void> deleteMemos(Set<int> memoIds) async {
    if (memoIds.isEmpty) return;
    await _repository.deleteByIds(memoIds.toList());

    // 追記先ごと消えたら終了
    if (memoIds.contains(_appendTarget?.id)) _endCurrentBlock();

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
