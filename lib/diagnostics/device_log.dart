import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// ============================================================
// アプリのログの書き残し
//
//   後から何が起きたかを追えるよう、出来事を3か所へ残す。
//   ・debugPrint（flutter run 中のコンソール。Android は logcat にも残る）
//   ・端末ログ（iOS のみ。Swift の DeviceLogChannel が os_log へ書く。release ビルドでも残るが約3日で消える）
//   ・アプリ内のファイル（1日1ファイル・14日分。開発用コンソールの「ログ」で読み、共有シートで書き出せる）
//   Swift 側で起きた出来事（オーディオの中断・経路の変化など）も、ここへ送られてきてファイルに残る。
//   文字起こしの本文など、利用者の発話は渡さないこと（端末ログは誰でも読める形で残る）。
//   書き方は「[分類] 出来事」。開発用コンソールは先頭の [分類] で絞り込む。
// ============================================================

class DeviceLog {
  static const MethodChannel _channel = MethodChannel('jp.momeo/device_log');

  // 残す日数（これより古い日のファイルは起動後の最初の書き込みで消す）
  static const _retentionDays = 14;

  // 1日のファイルの上限。録音の再開が繰り返されるなどで書き込みが暴走しても、容量を食い尽くさないため
  static const _maxBytesPerDay = 5 * 1024 * 1024;

  // ログを置くフォルダ（最初の書き込みで1回だけ用意する）
  static Future<Directory>? _logDirectoryFuture;

  // 書き込みを1本の列に並べ、行が混ざったり順番が入れ替わったりしないようにする
  static Future<void> _writeQueue = Future.value();

  // 今書いている日と、そのファイルの大きさ
  static String? _currentDay;
  static int _currentDayBytes = 0;
  static bool _dayLimitReached = false;

  // ---------------------------------
  // 起動時に1回呼ぶ: Swift 側の出来事を受け取り、起動したことを残す
  // ---------------------------------
  static void start() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'writeFromNative') {
        _appendToFile(DateTime.now(), call.arguments as String? ?? '');
      }
    });
    // momeo が起動し直したこと（iOS に終了させられたあとの起動など）が分かるようにする
    write('[app] 起動しました');
  }

  // ---------------------------------
  // 1件書き残す
  // ---------------------------------
  static void write(String message) {
    debugPrint(message);
    _appendToFile(DateTime.now(), message);
    if (!Platform.isIOS) return;
    // 書き残せなくても録音には関係ないので、待たずに失敗も無視する
    unawaited(
      _channel.invokeMethod<void>('write', message).catchError((Object _) {}),
    );
  }

  // ---------------------------------
  // 残っているログのファイル（新しい日が先頭）
  // ---------------------------------
  static Future<List<File>> logFiles() async {
    final directory = await _logDirectory();
    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.log'))
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  // ---------------------------------
  // ファイルへの追記
  // ---------------------------------
  // 時刻は呼ばれた瞬間のものを使う（列に並んで待つ間にずれないように）
  static void _appendToFile(DateTime at, String message) {
    _writeQueue = _writeQueue
        .then((_) => _appendLine(at, message))
        .catchError((Object _) {});
  }

  static Future<void> _appendLine(DateTime at, String message) async {
    final directory = await _logDirectory();
    final day = _formatDay(at);
    final file = File('${directory.path}/$day.log');

    // 日付が変わったら、その日のファイルの大きさを測り直す
    if (day != _currentDay) {
      _currentDay = day;
      _currentDayBytes = await file.exists() ? await file.length() : 0;
      _dayLimitReached = false;
    }
    if (_dayLimitReached) return;

    var bytes = utf8.encode('${_formatTime(at)} $message\n');
    if (_currentDayBytes + bytes.length > _maxBytesPerDay) {
      _dayLimitReached = true;
      bytes = utf8.encode('${_formatTime(at)} [log] この日のログが上限に達したので、ここから先は書きません\n');
    }
    await file.writeAsBytes(bytes, mode: FileMode.append);
    _currentDayBytes += bytes.length;
  }

  // ---------------------------------
  // ログのフォルダを用意し、古い日のファイルを消す
  // ---------------------------------
  static Future<Directory> _logDirectory() {
    return _logDirectoryFuture ??= _prepareLogDirectory();
  }

  static Future<Directory> _prepareLogDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final directory = Directory('${supportDirectory.path}/logs');
    await directory.create(recursive: true);

    // ファイル名は日付（yyyy-MM-dd.log）なので、名前の比較で古さが分かる
    final oldestDayToKeep = _formatDay(
      DateTime.now().subtract(const Duration(days: _retentionDays - 1)),
    );
    for (final entity in directory.listSync()) {
      if (entity is! File) continue;
      final fileName = entity.uri.pathSegments.last;
      if (fileName.compareTo(oldestDayToKeep) < 0) {
        await entity.delete();
      }
    }
    return directory;
  }

  static String _formatDay(DateTime at) {
    final month = at.month.toString().padLeft(2, '0');
    final day = at.day.toString().padLeft(2, '0');
    return '${at.year}-$month-$day';
  }

  static String _formatTime(DateTime at) {
    final hour = at.hour.toString().padLeft(2, '0');
    final minute = at.minute.toString().padLeft(2, '0');
    final second = at.second.toString().padLeft(2, '0');
    final millisecond = at.millisecond.toString().padLeft(3, '0');
    return '$hour:$minute:$second.$millisecond';
  }
}
