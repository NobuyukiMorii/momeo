import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel, PlatformException, rootBundle;
import 'package:path_provider/path_provider.dart';

import 'package:momeo/platform/asset_pack_delivery.dart';

// ============================================================
// STT モデルの「住所を返す窓口」（パス契約）
//
//   sherpa は実ファイルの「住所（パス）」からしかモデルを読めない。
//   一方、モデルの届き方は OS・ファイルごとにバラバラ:
//     - iOS の認識モデル   … アプリ同梱（Swift ブリッジ経由で実パスを取得）
//     - Android の認識モデル … 本番は自動DL（fast-follow パック）、開発は手置き（内部ストレージ）
//     - silero        … Flutter アセット同梱 → 端末へコピーして実パスを作る（両OS共通）
//
//   この「住所探しのバラバラさ」を窓口の中だけに隠し、
//   使う側（Step 7 の文字化・Step 9 のエンジン常駐）には実パスだけを返す。
//
//   扱うのは3ファイル:
//     - 認識モデル本体 (model.int8.onnx) … 音声 → 番号
//     - tokens        (tokens.txt)     … 番号 → 文字
//     - silero     (silero_vad.onnx) … 発話の区切り（VAD）
// ============================================================

// ---------------------------------
// 定数（ファイル名・正しいバイト数・契約）を1か所に集約
//   サイズは scripts/lib/stt_model_constants.sh と同じ値（整合性チェック用）。
//   ※ 同じバイト数を scripts/lib/stt_model_constants.sh でも使う。更新時は両方直すこと。
// ---------------------------------

// 認識モデル本体（音声 → 番号）。SenseVoice Small int8（2024-07-17）
const String _kModelFileName = 'model.int8.onnx';
const int _kModelExpectedBytes = 239233841;

// tokens（番号 → 文字）
const String _kTokensFileName = 'tokens.txt';
const int _kTokensExpectedBytes = 315894;

// silero VAD（アセット同梱 → 端末コピー）
//   入手元: https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx
//   ※ 認識モデルと違いリポジトリにコミット済み（git が中身を固定）。再ダウンロードはしない。
//   更新するときは assets/models/silero_vad.onnx を差し替え、下の期待バイト数も直す。
const String _kSileroAssetPath = 'assets/models/silero_vad.onnx';
const String _kSileroFileName = 'silero_vad.onnx';
const int _kSileroExpectedBytes = 643854;

// iOS ネイティブブリッジの契約。
//   ※ ios/Runner/SttModelChannel.swift と必ず一致させること（名前・メソッド・キー）。
const String _kIosChannelName = 'jp.momeo/stt_models';
const String _kIosGetModelPathsMethod = 'getModelPaths';
const String _kIosModelKey = 'model'; // 返ってくる辞書のキー
const String _kIosTokensKey = 'tokens';

// Android 開発機での手置き場所（内部ストレージ getApplicationSupportDirectory 配下の models/）。
//   外部ストレージ(Android/data)へ adb push したファイルは、アプリ（別UID）が読めない
//   （FUSE が別UIDのファイルを遮断し、chmod も無視される）。そのため確実に読める内部を使う。
//   置き方は /data/local/tmp 経由で run-as コピー（step06 の手順と一致）。
//   本番の自動配信（fast-follow）への差し替えは Step 8。
const String _kAndroidDevModelsSubDir = 'models';

// Android 本番配信（fast-follow アセットパック）の契約。
//   パック名は android/stt_models/build.gradle.kts の packName と必ず揃えること。
//   モデルはパック内の models/ サブフォルダに入る（自動DL完了後の実パスからの相対）。
const String _kAndroidModelPackName = 'stt_models';
const String _kAndroidPackModelsSubDir = 'models';

// ---------------------------------
// 1ファイルぶんの住所＋整合性
// ---------------------------------

class SttModelFile {
  const SttModelFile({
    required this.label,
    required this.fileName,
    required this.path,
    required this.expectedBytes,
    required this.actualBytes,
  });

  final String label; // 表示用ラベル（例「認識モデル本体」）
  final String fileName; // ファイル名
  final String path; // 実パス（見つからなければ空文字）
  final int expectedBytes; // 正しいバイト数
  final int actualBytes; // 実際のバイト数（見つからなければ -1）

  // ファイルが実際に置いてあるか
  bool get exists => actualBytes >= 0;

  // 存在し、かつサイズがちょうど正しいか（壊れ・途中切れを弾く）
  bool get isValid => exists && actualBytes == expectedBytes;
}

// ---------------------------------
// 3ファイルまとめ（窓口の返り値）
// ---------------------------------

class SttModels {
  const SttModels({
    required this.sttModel,
    required this.sttTokens,
    required this.silero,
  });

  final SttModelFile sttModel;
  final SttModelFile sttTokens;
  final SttModelFile silero;

  // dev catalog などで一覧表示するための並び
  List<SttModelFile> get all => [sttModel, sttTokens, silero];

  // 3つとも「決まった住所に正しいサイズで置いてある」か
  bool get allValid => all.every((file) => file.isValid);
}

// ---------------------------------
// 住所を返す窓口（パス契約の実装）
// ---------------------------------

class SttModelProvisioner {
  // iOS の住所を取りに行く通話線（Swift 側の SttModelChannel と対）
  static const MethodChannel _iosChannel = MethodChannel(_kIosChannelName);

  // 認識モデルの自動DL（fast-follow パック）の準備状態を扱う窓口。
  //   iOS など自動DLが無い環境では「常に完了」を返す空実装になる。
  final AssetPackDelivery _modelDelivery = AssetPackDelivery(_kAndroidModelPackName);

  // 3ファイルの住所を解決し、サイズまで測ってまとめて返す。
  // 見つからないファイルは exists=false / isValid=false になる（例外は投げない）。
  Future<SttModels> provision() async {
    final modelPaths = await _resolveModelPaths();
    final sileroPath = await ensureSilero();

    return SttModels(
      sttModel: await _measure(
        label: '認識モデル本体',
        fileName: _kModelFileName,
        path: modelPaths.modelPath,
        expectedBytes: _kModelExpectedBytes,
      ),
      sttTokens: await _measure(
        label: 'tokens',
        fileName: _kTokensFileName,
        path: modelPaths.tokensPath,
        expectedBytes: _kTokensExpectedBytes,
      ),
      silero: await _measure(
        label: 'silero VAD',
        fileName: _kSileroFileName,
        path: sileroPath,
        expectedBytes: _kSileroExpectedBytes,
      ),
    );
  }

  // silero をアセットから端末の書き込み領域へコピーし、その実パスを返す。
  //   VAD セクションもこの窓口を呼ぶ（silero の住所解決を1か所に集約）。
  //   すでにコピー済みなら何もしない。
  Future<String> ensureSilero() async {
    final supportDir = await getApplicationSupportDirectory();
    final file = File('${supportDir.path}/$_kSileroFileName');
    if (!await file.exists()) {
      final data = await rootBundle.load(_kSileroAssetPath);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
  }

  // ---------------------------------
  // 認識モデルの準備状態（自動DL）の公開口
  //   「いま未開始／DL中／完了／失敗か・進捗」を後段（dev 画面・起動時読み込み・
  //   待ち画面）へ渡す。実体は汎用ラッパー AssetPackDelivery への委譲。
  // ---------------------------------

  // 今の準備状態を1回だけ取得する。
  Future<AssetPackState> modelDownloadState() => _modelDelivery.currentState();

  // 準備状態の変化を流し続けるストリーム（DL中の進捗もここに流れる）。
  Stream<AssetPackState> watchModelDownload() => _modelDelivery.watchState();

  // 取得開始・再試行。未到着や失敗のときに呼ぶ。
  Future<void> requestModelDownload() => _modelDelivery.fetch();

  // ---------------------------------
  // 認識モデルの住所解決（OS で分岐。違いはここに隠す）
  // ---------------------------------

  Future<_ModelPaths> _resolveModelPaths() async {
    if (Platform.isIOS) return _resolveModelPathsForIos();
    if (Platform.isAndroid) return _resolveModelPathsForAndroid();
    // それ以外の OS は未対応（住所無しとして扱う）
    return const _ModelPaths(modelPath: '', tokensPath: '');
  }

  // iOS: 同梱したバンドルリソースの実パスを Swift ブリッジから受け取る。
  //   未登録などで見つからない場合は住所無し（カタログで NG 表示）。
  Future<_ModelPaths> _resolveModelPathsForIos() async {
    try {
      final paths = await _iosChannel.invokeMapMethod<String, String>(
        _kIosGetModelPathsMethod,
      );
      if (paths == null) return const _ModelPaths(modelPath: '', tokensPath: '');
      return _ModelPaths(
        modelPath: paths[_kIosModelKey] ?? '',
        tokensPath: paths[_kIosTokensKey] ?? '',
      );
    } on PlatformException {
      return const _ModelPaths(modelPath: '', tokensPath: '');
    }
  }

  // Android: 本番配信（fast-follow）と開発の手置きの両対応。
  //   1) まず自動DL（fast-follow パック）の実パスを試す。
  //   2) ただしパスが取れても、そこにモデルが実在するときだけ採用する。
  //      （日常の `flutter run` では空のパックがアプリに溶け込み、パスは取れても
  //        モデルは無い。そこで「パスの有無」ではなく「実ファイルの有無」で判定する。）
  //   3) 無ければ開発機の手置き（内部ストレージ）へフォールバックする。
  Future<_ModelPaths> _resolveModelPathsForAndroid() async {
    final fastFollowPaths = await _resolveModelPathsFromAndroidAssetPack();
    if (fastFollowPaths != null) return fastFollowPaths;
    return _resolveModelPathsFromAndroidDevPlacement();
  }

  // 自動DL（fast-follow パック）にモデルが届いていれば、その実パスを返す。
  //   パックが未到着、またはモデルが実在しなければ null（呼び出し側が手置きへ回す）。
  Future<_ModelPaths?> _resolveModelPathsFromAndroidAssetPack() async {
    final assetsPath = await AssetPackDelivery(_kAndroidModelPackName).assetsPath();
    if (assetsPath == null) return null;

    final modelsDir = '$assetsPath/$_kAndroidPackModelsSubDir';
    final modelPath = '$modelsDir/$_kModelFileName';
    // パスが取れても中身が無いことがあるので、実ファイルの存在で最終判断する。
    if (!await File(modelPath).exists()) return null;

    return _ModelPaths(
      modelPath: modelPath,
      tokensPath: '$modelsDir/$_kTokensFileName',
    );
  }

  // 開発機の手置き場所（内部ストレージ getApplicationSupportDirectory 配下の models/）の住所。
  //   adb で /data/local/tmp 経由 → run-as コピーで置く。silero と同じ場所に統一している。
  Future<_ModelPaths> _resolveModelPathsFromAndroidDevPlacement() async {
    final supportDir = await getApplicationSupportDirectory();
    final modelsDir = '${supportDir.path}/$_kAndroidDevModelsSubDir';
    return _ModelPaths(
      modelPath: '$modelsDir/$_kModelFileName',
      tokensPath: '$modelsDir/$_kTokensFileName',
    );
  }

  // ---------------------------------
  // 実パスのサイズを測り、1ファイルぶんの結果にまとめる
  // ---------------------------------

  Future<SttModelFile> _measure({
    required String label,
    required String fileName,
    required String path,
    required int expectedBytes,
  }) async {
    var actualBytes = -1;
    if (path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) {
        actualBytes = await file.length();
      }
    }
    return SttModelFile(
      label: label,
      fileName: fileName,
      path: path,
      expectedBytes: expectedBytes,
      actualBytes: actualBytes,
    );
  }
}

// 本体・tokens の2ファイルの住所をまとめて持ち回るだけの内部用の器
class _ModelPaths {
  const _ModelPaths({required this.modelPath, required this.tokensPath});

  final String modelPath;
  final String tokensPath;
}
