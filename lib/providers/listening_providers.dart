import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:momeo/database/app_database.dart';
import 'package:momeo/providers/database_providers.dart';
import 'package:momeo/providers/stt_providers.dart';
import 'package:momeo/repositories/voice_memo_repository.dart';
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

  @override
  Future<ListeningState> build() async {
    _repository = ref.watch(voiceMemoRepositoryProvider);
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _pipeline?.dispose();
      _pipeline = null;
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
      await pipeline.start();

      if (_disposed) {
        await pipeline.dispose();
        return;
      }
      _pipeline = pipeline;
    } catch (error) {
      // 準備待ち画面やエラー表示はまだ無い。ここではログに記録するだけ
      debugPrint('[listening] リスニングを開始できませんでした: $error');
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

  // タイピング演出を使い切ったときにページから呼ばれる（再表示時の再再生を防ぐ）
  void onTypingComplete(int memoId) {
    if (_disposed) return;
    final current = state.value;
    if (current == null || current.typeInMemoId != memoId) return;
    state = AsyncData(current.withTypeInConsumed());
  }
}
