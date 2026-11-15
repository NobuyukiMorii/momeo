#!/usr/bin/env bash
# 端末とビルドモードに応じて、アプリをビルドして動かす。
# 使い方:bash scripts/run_on_device.sh <デバイスID> <ビルドモード> [確認用のスイッチ]
#   確認用のスイッチは --dart-define に渡す。カンマ区切りで複数指定できる（例: FAKE_LANGUAGE_DOWNLOAD_SECONDS=30）

# 失敗したら止める
set -euo pipefail

# このスクリプトの場所
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FLUTTER_DEVICE_ID="${1:-}" # デバイスID
BUILD_MODE="${2:-debug}" # ビルドモード
DART_DEFINES="${3:-}" # 確認用のスイッチ（なければ空）

# ---------------------------------
# 引数を確かめる
# ---------------------------------
if [ -z "$FLUTTER_DEVICE_ID" ]; then # # デバイスIDがないなら
  # エラー
  echo "✗ デバイスIDを指定してください（ID は flutter devices で確認）" >&2

  # 先へ進ませない
  exit 1
fi

# ---------------------------------
# flutter run で動かす
# ---------------------------------
# 前回の iOS ビルドの残骸が残っていたらクリーンする
bash "$SCRIPT_DIR/clean_stale_ios_build.sh" "$FLUTTER_DEVICE_ID"

# 確認用のスイッチを --dart-define の並びにする
DART_DEFINE_ARGS=()
if [ -n "$DART_DEFINES" ]; then
  IFS=',' read -r -a DEFINE_ITEMS <<< "$DART_DEFINES"
  for define_item in "${DEFINE_ITEMS[@]}"; do
    DART_DEFINE_ARGS+=("--dart-define=$define_item")
  done
  echo "✓ 確認用のスイッチを付けて起動します: ${DART_DEFINE_ARGS[*]}"
fi

# 起動する
flutter run --"$BUILD_MODE" -d "$FLUTTER_DEVICE_ID" ${DART_DEFINE_ARGS[@]+"${DART_DEFINE_ARGS[@]}"}
