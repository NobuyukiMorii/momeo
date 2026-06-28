#!/usr/bin/env bash
#
# オンデバイス STT 用モデル（NeMo）を手元にダウンロードするスクリプト。
#
#   何をするか:
#     1. sherpa-onnx 作者本人の公式置き場（Hugging Face）から2つのファイルを落とす
#          - model.int8.onnx … 音声を文字にする「脳」本体（約625MB）。
#                              ただし出力は文字ではなく「番号の列」。
#          - tokens.txt       … その「番号 → 文字」の対応表（約28KB）。
#                              脳が出した番号をこの表で文字に直して、初めて文章になる。
#       ※ この2つは必ずペア。番号の振り方はモデルごとに違うので、
#         別バージョンの表を混ぜると文字化けする。だから同じバージョンで揃える。
#     2. 落としたファイルのサイズが「ちょうど正しいバイト数か」を確かめる
#          （途中で切れた半端なファイルを弾くため。ハッシュ検証はしない）
#     3. プロジェクト直下の .dev_models/ に置く
#
#   使い方（プロジェクトのどこからでも実行できる）:
#     bash scripts/fetch_nemo_model.sh
#
#   ※ ここでは「落として確かめる」だけ。iOS への同梱・Android への配置は別の手順。

set -euo pipefail

# ---------------------------------
# 取得元と、取得するファイルの定義
# ---------------------------------

# 取得元（sherpa-onnx の主要メンテナ Fangjun Kuang の公式アカウント）
readonly MODEL_REPO="csukuangfj/sherpa-onnx-nemo-parakeet-tdt_ctc-0.6b-ja-35000-int8"

# 取得するバージョン（コミットハッシュ）。
#   「main」（最新を指す動く矢印）ではなく特定バージョンに固定している。
#   理由: 作者がファイルを差し替えると中身が変わり、下のバイト数チェックが
#         （壊れていないのに）失敗してしまう。固定すれば中身が背後で変わらず、
#         バイト数も永久に正しいまま・誰の環境でも同じファイルが手に入る。
#   更新したいとき: 新しいバージョンの「コミットハッシュ」と、それに対応する
#                   下の MODEL_EXPECTED_BYTES / TOKENS_EXPECTED_BYTES を書き換える。
readonly MODEL_COMMIT="bef18eb066808c90bd0f5df5be685767b0732de8" # 2025-07-09 時点の main

# 上の3つから組み立てた、実際に叩く取得元 URL
readonly MODEL_BASE_URL="https://huggingface.co/$MODEL_REPO/resolve/$MODEL_COMMIT"

# ファイル名と、正しい場合のバイト数（このバイト数とピッタリ一致しなければ失敗扱い）
#   ※ 同じバイト数を lib/stt/stt_model_provisioner.dart でも使う。更新時は両方直すこと。
readonly MODEL_FILE="model.int8.onnx"
readonly MODEL_EXPECTED_BYTES=655542604

readonly TOKENS_FILE="tokens.txt"
readonly TOKENS_EXPECTED_BYTES=28557

# ---------------------------------
# 置き場所（このスクリプトの場所からプロジェクト直下を割り出す）
# ---------------------------------

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly DEST_DIR="$PROJECT_ROOT/.dev_models"

# iOS の所定フォルダ。ここに置いたファイルを Xcode の「バンドルリソース」として同梱する
readonly IOS_MODELS_DIR="$PROJECT_ROOT/ios/Runner/Models"

# ---------------------------------
# 1ファイルを「落として、サイズを確かめる」係
#   $1: ファイル名  $2: 期待するバイト数
# ---------------------------------

download_and_verify() {
  local file_name="$1"
  local expected_bytes="$2"
  local url="$MODEL_BASE_URL/$file_name"
  local dest_path="$DEST_DIR/$file_name"

  # すでに正しいサイズで置いてあるなら、落とし直さない
  if [ -f "$dest_path" ] && [ "$(file_size_in_bytes "$dest_path")" = "$expected_bytes" ]; then
    echo "✓ $file_name はすでに正しいサイズで存在します（再ダウンロードしません）"
    return
  fi

  echo "↓ $file_name をダウンロードします …"
  #   -L      : リダイレクトを追う（Hugging Face は途中でリダイレクトする）
  #   -f      : サーバがエラーを返したら失敗にする
  #   --retry : 一時的な失敗は数回まで自動で再試行
  #   -C -    : 途中まで落ちていれば、その続きから再開する
  curl -L -f --retry 3 -C - -o "$dest_path" "$url"

  # 落とした直後にサイズを確認する
  local actual_bytes
  actual_bytes="$(file_size_in_bytes "$dest_path")"
  if [ "$actual_bytes" != "$expected_bytes" ]; then
    echo "✗ $file_name のサイズが一致しません（期待 $expected_bytes / 実際 $actual_bytes バイト）" >&2
    echo "  ダウンロードが途中で切れた可能性があります。もう一度このスクリプトを実行してください。" >&2
    exit 1
  fi
  echo "✓ $file_name を確認しました（$actual_bytes バイト）"
}

# ファイルのバイト数を返す（OS の違いを気にせず使えるよう wc を使う）
file_size_in_bytes() {
  wc -c < "$1" | tr -d ' '
}

# ---------------------------------
# iOS の所定フォルダ（ios/Runner/Models）へコピーする係
#   sherpa は実ファイルのパスが要る。iOS ではここに置いたファイルを
#   Xcode の「バンドルリソース」として同梱する（Xcode への登録は別作業）。
# ---------------------------------

place_for_ios() {
  mkdir -p "$IOS_MODELS_DIR"
  for file_name in "$MODEL_FILE" "$TOKENS_FILE"; do
    local src="$DEST_DIR/$file_name"
    local dst="$IOS_MODELS_DIR/$file_name"
    # すでに同じサイズで置いてあればコピーし直さない
    if [ -f "$dst" ] && [ "$(file_size_in_bytes "$dst")" = "$(file_size_in_bytes "$src")" ]; then
      echo "✓ iOS: $file_name は配置済み"
      continue
    fi
    echo "→ iOS へコピー: $file_name"
    cp "$src" "$dst"
  done
  echo "✓ iOS の所定フォルダへ配置しました: $IOS_MODELS_DIR"
}

# ---------------------------------
# 本体
# ---------------------------------

main() {
  mkdir -p "$DEST_DIR"
  echo "置き場所: $DEST_DIR"
  echo

  download_and_verify "$MODEL_FILE" "$MODEL_EXPECTED_BYTES"
  download_and_verify "$TOKENS_FILE" "$TOKENS_EXPECTED_BYTES"

  echo
  place_for_ios

  echo
  echo "完了しました。NeMo が揃っています:"
  echo "  ダウンロード先: $DEST_DIR"
  echo "  iOS 配置先:     $IOS_MODELS_DIR"
}

main "$@"
