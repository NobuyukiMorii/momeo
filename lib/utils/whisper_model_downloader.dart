import 'dart:io';

import 'package:whisper_flutter_new/whisper_flutter_new.dart' show WhisperModel;

// =====================================================================
// WhisperModelDownloader — Whisper(ggml) モデルを「壊さずに」ダウンロードする
//
// whisper_flutter_new 同梱の downloadModel は HTTP ステータスや
// Content-Length を検証せず、途中で切れたストリームをそのまま保存する。
// その結果、不完全（数MB）なモデルが「成功」として残り、whisper.cpp が
// それを読み込んで NULL コンテキストになり、ネイティブ側でクラッシュする。
//
// ここではその弱点を塞ぐため、次の保証を付ける。
//   ・HTTP 200 以外は失敗として扱う
//   ・サーバ申告サイズ（Content-Length）と実書き込みサイズの一致を検証
//   ・一時ファイル（.download）に書いてから本ファイル名へリネーム（原子的差し替え）
//   ・途中で切れたら本ファイルは作られない（＝壊れたモデルを使わせない）
//   ・既存ファイルもサイズの下限でざっくり健全性チェックし、壊れていれば再取得
// =====================================================================
class WhisperModelDownloader {
  // HuggingFace（whisper.cpp 公式 ggml 配布）
  static const String _defaultHost =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';

  // ---------------------------------
  // 「壊れていない」と見なす最小サイズ（バイト）
  // 途中で切れたダウンロード（数MB）を弾くための下限。実サイズより十分小さい値にする。
  // ---------------------------------
  static int _minValidBytes(WhisperModel model) {
    const int mb = 1024 * 1024;
    switch (model) {
      case WhisperModel.tiny:
        return 50 * mb; // 実サイズ 約74MB
      case WhisperModel.base:
        return 100 * mb; // 実サイズ 約141MB
      case WhisperModel.small:
        return 400 * mb; // 実サイズ 約465MB
      case WhisperModel.medium:
        return 1200 * mb; // 実サイズ 約1.4GB
      case WhisperModel.largeV1:
      case WhisperModel.largeV2:
        return 2500 * mb; // 実サイズ 約2.9GB
      case WhisperModel.none:
        return 1 * mb;
    }
  }

  // ---------------------------------
  // 端末上のファイルが「完全とみなせる」かを判定する
  // （存在し、かつ最小サイズを満たしていれば true）
  // ---------------------------------
  static bool isValidFile(String filePath, int minValidBytes) {
    final file = File(filePath);
    if (!file.existsSync()) return false;
    return file.lengthSync() >= minValidBytes;
  }

  // 標準（fp16）モデルが完全に揃っているかの判定
  static bool isValidModelFile(WhisperModel model, String destinationDir) {
    return isValidFile(model.getPath(destinationDir), _minValidBytes(model));
  }

  // ---------------------------------
  // 標準（fp16）モデルを用意する（完全なファイルが無ければ HuggingFace からDL）
  //
  // onProgress(received, total) は受信中に呼ばれる。total はサーバが
  // サイズを申告しない場合のみ null になる。
  // ---------------------------------
  static Future<void> ensureModel({
    required WhisperModel model,
    required String destinationDir,
    String? host,
    void Function(int received, int? total)? onProgress,
  }) async {
    final String baseHost =
        (host == null || host.isEmpty) ? _defaultHost : host;
    await ensureFile(
      url: Uri.parse('$baseHost/ggml-${model.modelName}.bin'),
      destinationPath: model.getPath(destinationDir),
      minValidBytes: _minValidBytes(model),
      onProgress: onProgress,
    );
  }

  // ---------------------------------
  // 任意の URL を任意のパスへ「検証付き」でダウンロードする（中核処理）
  //
  // 量子化モデル（ggml-small-q5_1.bin 等）のように WhisperModel enum で
  // 表せないファイルも、URL と保存先を直接指定して安全に取得するための入口。
  //   ・HTTP 200 以外は失敗
  //   ・サーバ申告サイズ（Content-Length）と実書き込みサイズの一致を検証
  //   ・.download 一時ファイルに書いてから本ファイル名へ原子的にリネーム
  //   ・既に完全なファイルがあれば何もしない
  // ---------------------------------
  static Future<void> ensureFile({
    required Uri url,
    required String destinationPath,
    required int minValidBytes,
    void Function(int received, int? total)? onProgress,
  }) async {
    // すでに完全なファイルがあるなら何もしない
    if (isValidFile(destinationPath, minValidBytes)) return;

    final File finalFile = File(destinationPath);
    // 壊れた残骸が残っていれば消してから取り直す
    if (finalFile.existsSync()) {
      finalFile.deleteSync();
    }
    // 保存先ディレクトリが無ければ作る
    final Directory parentDir = finalFile.parent;
    if (!parentDir.existsSync()) {
      parentDir.createSync(recursive: true);
    }

    final File partFile = File('$destinationPath.download');
    if (partFile.existsSync()) {
      partFile.deleteSync();
    }

    final HttpClient httpClient = HttpClient();
    try {
      final HttpClientRequest request = await httpClient.getUrl(url);
      final HttpClientResponse response = await request.close();

      if (response.statusCode != 200) {
        throw Exception(
          'ファイル取得に失敗 (HTTP ${response.statusCode}) $url',
        );
      }

      // 不明なときは -1
      final int total = response.contentLength;

      // 一時ファイルに同期書き込み（writeFromSync が自然なバックプレッシャになる）
      final RandomAccessFile raf = partFile.openSync(mode: FileMode.write);
      int received = 0;
      try {
        await for (final List<int> chunk in response) {
          raf.writeFromSync(chunk);
          received += chunk.length;
          onProgress?.call(received, total < 0 ? null : total);
        }
      } finally {
        raf.closeSync();
      }

      // -----------------------------------------------------------------
      // 完全性チェック
      // -----------------------------------------------------------------
      final int written = partFile.lengthSync();

      // サーバが申告したサイズと食い違えば不完全とみなす
      if (total >= 0 && written != total) {
        partFile.deleteSync();
        throw Exception('ダウンロードが不完全です ($written / $total bytes)');
      }
      // 念のため最小サイズの下限も確認する
      if (written < minValidBytes) {
        partFile.deleteSync();
        throw Exception('ファイルが小さすぎます ($written bytes)');
      }

      // 検証を通ったので、本ファイル名へ原子的に差し替える
      partFile.renameSync(destinationPath);
    } finally {
      httpClient.close();
    }
  }
}
