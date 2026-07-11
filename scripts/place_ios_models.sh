#!/usr/bin/env bash
#
# NeMo モデルを iOS の所定フォルダ（ios/Runner/Models/）へ配置するスクリプト
# （無ければコピーする）。ここに置いたファイルを Xcode の「バンドルリソース」
# として同梱する（Xcode への登録は済んでいる前提）。
#
#   使い方:
#     bash scripts/place_ios_models.sh              # 無条件に配置（build-ios 用）
#     bash scripts/place_ios_models.sh [デバイスID]  # Android 端末ならスキップ
#       デバイスIDが adb devices に見える = Android なので iOS 配置は不要、
#       見えない = iOS 端末とみなして配置する（place_android_device_models.sh の鏡像）
#
#   前提: .dev_models/ にモデルがあること（scripts/download_nemo_model.sh で取得）

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly DEV_MODELS_DIR="$PROJECT_ROOT/.dev_models"
readonly IOS_MODELS_DIR="$PROJECT_ROOT/ios/Runner/Models"

# adb 端末まわりの共通ヘルパー（list_android_devices / resolve_adb_serial）
source "$SCRIPT_DIR/lib/adb_devices.sh"

# ファイル名の共通定数（MODEL_FILE / TOKENS_FILE）
source "$SCRIPT_DIR/lib/nemo_model_constants.sh"

# 引数のデバイスID（Flutter devices が表示する ID。省略可）
FLUTTER_DEVICE_ID="${1:-}"

# ---------------------------------
# ファイルのバイト数
# ---------------------------------
file_size_in_bytes() {
  wc -c < "$1" | tr -d ' '
}

# ---------------------------------
# 1. 対象が iOS かを確かめる（Android 端末なら何もしない）
# ---------------------------------

if [ -n "$FLUTTER_DEVICE_ID" ] \
  && resolve_adb_serial "$FLUTTER_DEVICE_ID" >/dev/null; then
  echo "· $FLUTTER_DEVICE_ID は Android 端末のため、iOS への配置はスキップします"
  exit 0
fi

# ---------------------------------
# 2. .dev_models/ から所定フォルダへコピーする（同じサイズなら何もしない）
# ---------------------------------

mkdir -p "$IOS_MODELS_DIR"

for file_name in "$MODEL_FILE" "$TOKENS_FILE"; do
  src="$DEV_MODELS_DIR/$file_name"
  dst="$IOS_MODELS_DIR/$file_name"

  if [ ! -f "$src" ]; then
    echo "✗ $src がありません。" >&2
    echo "  先に bash scripts/download_nemo_model.sh を実行してください。" >&2
    exit 1
  fi

  # すでに同じサイズで置いてあればコピーし直さない
  if [ -f "$dst" ] && [ "$(file_size_in_bytes "$dst")" = "$(file_size_in_bytes "$src")" ]; then
    echo "✓ iOS: $file_name は配置済み"
    continue
  fi

  echo "→ iOS へコピー: $file_name"
  cp "$src" "$dst"
done

echo "✓ iOS の所定フォルダへ配置しました: $IOS_MODELS_DIR"
