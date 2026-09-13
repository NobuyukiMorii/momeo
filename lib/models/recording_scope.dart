import 'package:flutter/material.dart';
import 'package:momeo/foundation/app_colors.dart';

// ============================================================
// RecordingScope — いつ録音するか
//
//   端末に保存しているのは「バックグラウンド録音を有効にしているか」という
//   真偽値ひとつで、この enum はそれを画面に出す形へ言い換えたもの。
//   文言と状態の色をここに集めておき、録音設定パネルの状態行と選択肢カードの
//   どちらからも同じものを読む。
// ============================================================
enum RecordingScope {
  // このアプリを使っている間だけ録音する
  foregroundOnly(
    title: 'このアプリを使ってる時だけ録音',
    description: 'ほかのアプリを使っている間やホーム画面では録音を止めます。',
    // アプリ内だけで完結するので、弱い注意の色
    dotColor: AppColors.notice,
  ),

  // ほかのアプリを使っていても録音し続ける
  background(
    title: 'ほかのアプリを使っていても録音',
    description: 'ほかのアプリを使っている間やホーム画面でも録音し続けます。',
    // 画面を離れても録り続けるので、強い注意の色
    dotColor: AppColors.caution,
  );

  const RecordingScope({
    required this.title,
    required this.description,
    required this.dotColor,
  });

  // 選択肢カードのタイトル。録音設定パネルの状態行にもそのまま出す
  final String title;

  // 選択肢カードの説明文
  final String description;

  // 今どの範囲かを示すドットの色
  final Color dotColor;

  // この範囲を選ぶと、バックグラウンド録音が有効になるか
  bool get enablesBackgroundRecording => this == background;

  // 保存されている設定値に対応する範囲
  static RecordingScope of({required bool isBackgroundRecordingEnabled}) {
    return isBackgroundRecordingEnabled ? background : foregroundOnly;
  }
}
