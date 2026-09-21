#!/usr/bin/env bash
#
# オンデバイス STT 用モデル（SenseVoice Small int8）を手元にダウンロードするスクリプト。
#
#   何をするか:
#     1. sherpa-onnx の公式リリースから書庫（tar.bz2）を落とす
#     2. 書庫全体の SHA256 を照合する（途中で切れた・差し替えられたものを弾く）
#     3. 書庫の中から2つのファイルだけを取り出して .dev_models/ に置く
#          - model.int8.onnx … 音声を文字にする「脳」本体（約239MB）。
#                              ただし出力は文字ではなく「番号の列」。
#          - tokens.txt       … その「番号 → 文字」の対応表（約316KB）。
#                              脳が出した番号をこの表で文字に直して、初めて文章になる。
#       ※ この2つは必ずペア。番号の振り方はモデルごとに違うので、
#         別バージョンの表を混ぜると文字化けする。だから同じ書庫から取り出す。
#
#   使い方（プロジェクトのどこからでも実行できる）:
#     bash scripts/download_stt_model.sh
#
#   ※ ここでは「落として確かめる」だけ。配置は別のスクリプトが行う。
#      iOS への同梱     … scripts/place_ios_models.sh
#      Android への配置 … scripts/place_android_device_models.sh（開発時の手置き）
#                         scripts/place_android_pack_models.sh（AAB 用パック）

set -euo pipefail

# ---------------------------------
# 置き場所（このスクリプトの場所からプロジェクト直下を割り出す）
# ---------------------------------

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly DEV_MODELS_DIR="$PROJECT_ROOT/.dev_models"

# 取得元・ファイル名・正しいバイト数の共通定数
source "$SCRIPT_DIR/lib/stt_model_constants.sh"

readonly DEST_DIR="$DEV_MODELS_DIR/$MODEL_SUB_DIR"
readonly ARCHIVE_PATH="$DEV_MODELS_DIR/$MODEL_ARCHIVE_NAME"

# ファイルのバイト数を返す（OS の違いを気にせず使えるよう wc を使う）
file_size_in_bytes() {
  wc -c < "$1" | tr -d ' '
}

# 2ファイルとも正しいサイズで置いてあるか
is_already_placed() {
  [ -f "$DEST_DIR/$MODEL_FILE" ] \
    && [ -f "$DEST_DIR/$TOKENS_FILE" ] \
    && [ "$(file_size_in_bytes "$DEST_DIR/$MODEL_FILE")" = "$MODEL_EXPECTED_BYTES" ] \
    && [ "$(file_size_in_bytes "$DEST_DIR/$TOKENS_FILE")" = "$TOKENS_EXPECTED_BYTES" ]
}

# ---------------------------------
# 1. 書庫を落として、SHA256 を照合する
# ---------------------------------

download_archive() {
  # すでに正しい書庫が手元にあるなら落とし直さない
  if echo "$MODEL_ARCHIVE_SHA256  $ARCHIVE_PATH" | shasum -a 256 -c - >/dev/null 2>&1; then
    echo "✓ 書庫はすでに手元にあります（再ダウンロードしません）"
    return
  fi

  echo "↓ 書庫をダウンロードします …"
  #   -L      : リダイレクトを追う
  #   -f      : サーバがエラーを返したら失敗にする
  #   --retry : 一時的な失敗は数回まで自動で再試行
  #   .part に落としてから差し替えるので、途中で切れた書庫が残らない
  curl -L -f --retry 3 -o "$ARCHIVE_PATH.part" "$MODEL_ARCHIVE_URL"
  echo "$MODEL_ARCHIVE_SHA256  $ARCHIVE_PATH.part" | shasum -a 256 -c -
  mv "$ARCHIVE_PATH.part" "$ARCHIVE_PATH"
  echo "✓ 書庫を確認しました"
}

# ---------------------------------
# 2. 書庫の中から2ファイルだけを取り出す
# ---------------------------------

extract_two_files() {
  mkdir -p "$DEST_DIR"
  python3 - "$ARCHIVE_PATH" "$DEST_DIR" "${MODEL_ARCHIVE_NAME%.tar.bz2}" "$MODEL_FILE" "$TOKENS_FILE" <<'PY'
import pathlib
import sys
import tarfile

archive_path, dest_dir, inner_dir_name = sys.argv[1:4]
file_names = sys.argv[4:]
dest = pathlib.Path(dest_dir)

with tarfile.open(archive_path) as archive:
    for file_name in file_names:
        member = archive.getmember(f'{inner_dir_name}/{file_name}')
        if not member.isfile() or member.size <= 0:
            raise SystemExit(f'書庫の中の {file_name} が壊れています')
        (dest / file_name).write_bytes(archive.extractfile(member).read())
PY
}

# ---------------------------------
# 3. 取り出したファイルのサイズを確かめる
# ---------------------------------

verify_size() {
  local file_name="$1"
  local expected_bytes="$2"
  local actual_bytes
  actual_bytes="$(file_size_in_bytes "$DEST_DIR/$file_name")"

  if [ "$actual_bytes" != "$expected_bytes" ]; then
    echo "✗ $file_name のサイズが一致しません（期待 $expected_bytes / 実際 $actual_bytes バイト）" >&2
    echo "  $ARCHIVE_PATH を消して、もう一度このスクリプトを実行してください。" >&2
    exit 1
  fi
  echo "✓ $file_name を確認しました（$actual_bytes バイト）"
}

# ---------------------------------
# 本体
# ---------------------------------

main() {
  mkdir -p "$DEV_MODELS_DIR"
  echo "置き場所: $DEST_DIR"
  echo

  if is_already_placed; then
    echo "✓ モデルはすでに正しいサイズで揃っています"
    return
  fi

  download_archive
  extract_two_files
  verify_size "$MODEL_FILE" "$MODEL_EXPECTED_BYTES"
  verify_size "$TOKENS_FILE" "$TOKENS_EXPECTED_BYTES"

  echo
  echo "✓ SenseVoice のダウンロードが揃っています: $DEST_DIR"
}

main "$@"
