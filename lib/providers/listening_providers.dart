import 'dart:async';

// アプリがバックグラウンドかフォアグラウンドかを把握するための3つのクラスを取り込む
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:momeo/database/app_database.dart';
import 'package:momeo/diagnostics/device_log.dart';
import 'package:momeo/providers/database_providers.dart';
import 'package:momeo/providers/stt_providers.dart';
import 'package:momeo/repositories/edited_document_plan.dart';
import 'package:momeo/repositories/voice_memo_repository.dart';
import 'package:momeo/stt/stt_audio_worker.dart';
import 'package:momeo/stt/stt_listening_pipeline.dart';
import 'package:momeo/stt/stt_model_provisioner.dart';

// ============================================================
// listeningProvider — リスニング画面の状態を一元管理する
//
//   ページ（listening_page）は watch して描画するだけの View に徹する。
//   録音パイプラインの生成・開始・破棄もこの Notifier が持つ。
//
//   録音するのは、アプリを開いている間だけ。バックグラウンドに移ったら止め、フォアグラウンドに戻ったら始め直す。
//   録音している間は、自動ロックで止まらないよう画面を消さない。
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

  // 発話が文字化されずに捨てられた（他のアプリが鳴り始めたときなど）。
  // 文字化の結果は届かないので、発話中も結果待ちも解く
  ListeningState withSpeechDiscarded() {
    return ListeningState(
      memos: memos,
      speechActive: false,
      awaitingTranscription: false,
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

  // 編集を終えた文書を保存した（編集した段落を差し替え、それより後ろの段落はそのまま残す）
  //   editedIds は編集を始めた時点の段落の id、savedMemos は保存した段落（上から順）
  ListeningState withMemosEdited({
    required Set<int> editedIds,
    required List<VoiceMemo> savedMemos,
  }) {
    return ListeningState(
      memos: [
        // 編集の間に増えた段落（新しい順のまま）
        for (final memo in memos)
          if (!editedIds.contains(memo.id)) memo,
        // 保存した段落（新しい順に直す）
        ...savedMemos.reversed,
      ],
      speechActive: speechActive,
      awaitingTranscription: awaitingTranscription,
      appendTargetId: appendTargetId,
      typeInMemoId: typeInMemoId,
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

  @override
  Future<ListeningState> build() async {
    _repository = ref.watch(voiceMemoRepositoryProvider);
    _disposed = false;

    // アプリのライフサイクルに合わせた録音の停止・再開を管理するリスナーを作成
    final lifecycleListener = AppLifecycleListener(
      onPause: _onAppPaused, // バックグラウンド遷移で録音を止める
      onResume: _onAppResumed, // フォアグラウンド復帰で再開する
    );

    ref.onDispose(() {
      _disposed = true;
      lifecycleListener.dispose();
      _pipeline?.dispose();
      _pipeline = null;
      // 録音をやめたので、画面の自動ロックを元に戻す
      unawaited(WakelockPlus.disable());
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
        onSpeechDiscarded: _onSpeechDiscarded,
      );

      await pipeline.start();

      if (_disposed) {
        await pipeline.dispose();
        return;
      }
      _pipeline = pipeline;

      // 録音している間は、自動ロックで録音が止まらないよう画面を消さない
      unawaited(WakelockPlus.enable());

      // _startPipeline() の最中にアプリがバックグラウンドへ移ると、_onAppPaused の時点で録音がまだ無い。
      // その場合の保険として、今バックグラウンドにいるなら始まったばかりの録音をここで止める
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
        await pipeline.stop();
      }
    } catch (error) {
      // 準備待ち画面やエラー表示はまだ無い。ここではログに記録するだけ
      DeviceLog.write('[listening] リスニングを開始できませんでした: $error');
    }
  }

  // ---------------------------------
  // アプリがバックグラウンドに移ったときの録音の停止
  // ---------------------------------
  void _onAppPaused() {
    DeviceLog.write('[listening] 背面に回りました。録音を止めます');
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
  //   バックグラウンドに移っていたなら止めているので始め直す。コントロールセンターを開いただけなど、
  //   バックグラウンドに移らずに戻ったときは録音が続いているので、止まっていないかを確かめる（どちらも ensureRunning が担う）
  // ---------------------------------
  Future<void> _onAppResumed() async {
    DeviceLog.write('[listening] 前面に戻りました。録音を始めるか、止まっていないか確かめます');
    try {
      await _pipeline?.ensureRunning();
    } catch (error) {
      // バックグラウンド中の権限取り消しなどはログのみ。権限の取り直しは RootView が担う
      DeviceLog.write('[listening] リスニングを再開できませんでした: $error');
    }
  }

  // 発話が文字化されずに捨てられたら、「.」の結果待ちを解く（結果は届かないため）
  void _onSpeechDiscarded() {
    if (_disposed) return;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.withSpeechDiscarded());
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
  //   あり: 追記先があればその末尾へ書き足し、無ければ新しく起こす。発話の記録にも残す
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
    final int memoId;
    if (appendTarget == null) { // 追記先が無い
      memoId = await _startNewMemo(content); // 新しいブロックを作成
    } else { // 追記先がある
      memoId = await _appendToTarget(appendTarget, content); // そのブロックの末尾に追記
    }

    // 次の発話を同じブロックに入れるかどうかの起点にする
    _lastAppendedAt = DateTime.now();

    // 認識したままの文字列を、発話の記録に残す（あとで本文と比べられるように）
    await _repository.insertUtterance(
      content: content,
      recognizedAt: DateTime.now(),
      durationSec: result.durationSec,
      memoId: memoId,
    );
  }

  // ---------------------------------
  // 新しいブロックを起こし、その id を返す（以後の発話は、このブロックへ追記していく）
  // ---------------------------------
  Future<int> _startNewMemo(String content) async {
    final createdAt = _speechStartedAt ?? DateTime.now();
    final memo = await _repository.insert(content: content, createdAt: createdAt);
    // 次の追記先にする
    _appendTarget = memo;

    if (_disposed) return memo.id;
    final current = state.value;
    if (current == null) return memo.id;
    state = AsyncData(current.withMemoAdded(memo));
    return memo.id;
  }

  // ---------------------------------
  // ブロックの末尾に追記し、そのブロックの id を返す
  // ---------------------------------
  Future<int> _appendToTarget(VoiceMemo appendTarget, String content) async {
    // 発話と発話の間は区切らず、そのままつなげる
    final appended = '${appendTarget.content}$content';
    // 追記先の内容を更新
    await _repository.updateContent(id: appendTarget.id, content: appended);
    // state 用にメモを作り直す
    final memo = appendTarget.copyWith(content: appended);
    // 次の追記先として持ち直す
    _appendTarget = memo;

    // 画面を離れた後は state に触れない（DB への保存はここまでで済んでいる）
    if (_disposed) return memo.id;
    // 今の状態
    final current = state.value;
    // 読み込み中でまだ状態が無ければ、表示の更新はしない
    if (current == null) return memo.id;
    // 最新のメモを、書き足した後の内容に差し替える
    state = AsyncData(current.withMemoAppended(
      memo,
      // 新しく足した分だけ1文字ずつ表示する（前からある本文はそのまま）
      typeInFrom: appended.length - content.length,
    ));
    return memo.id;
  }

  // ---------------------------------
  // 一覧の編集が始まった
  //   書き直している段落へ声が足されないよう、今のブロックへの追記を終える（次の発話は末尾の新しい段落になる）
  // ---------------------------------
  void onEditingStarted() {
    _endCurrentBlock();
  }

  // ---------------------------------
  // 一覧の編集を終えた文書を、段落ごとに DB の行へ戻して保存する
  //   editedIds: 編集を始めた時点で書き直せた段落の id
  //   paragraphs: 編集の後の段落（上から順）
  // ---------------------------------
  Future<void> saveEditedDocument({
    required List<int> editedIds,
    required List<EditedParagraph> paragraphs,
  }) async {
    final current = state.value;
    if (current == null) return;
    final editedIdSet = editedIds.toSet();
    final plan = EditedDocumentPlan.build(
      // 編集の前の段落（上から順）
      beforeMemos: [
        for (final memo in current.memos.reversed)
          if (editedIdSet.contains(memo.id)) memo,
      ],
      editedParagraphs: paragraphs,
    );
    if (!plan.hasChanges) return;

    final savedMemos = await _repository.saveEditedMemos(
      paragraphs: plan.paragraphs,
      deletedIds: plan.deletedIds,
      changedText: plan.changedText,
    );

    // --- 画面へ反映する（保存の間に増えた段落も残す）
    if (_disposed) return;
    final latest = state.value;
    if (latest == null) return;
    state = AsyncData(latest.withMemosEdited(editedIds: editedIdSet, savedMemos: savedMemos));
  }

  // タイピング演出を使い切ったときにページから呼ばれる（再表示時の再再生を防ぐ）
  void onTypingComplete(int memoId) {
    if (_disposed) return;
    final current = state.value;
    if (current == null || current.typeInMemoId != memoId) return;
    state = AsyncData(current.withTypeInConsumed());
  }
}
