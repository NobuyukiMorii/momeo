#!/usr/bin/env bash
# 端末とビルドモードに応じて、アプリをビルドして動かす。
# 使い方:bash scripts/run_on_device.sh <デバイスID> <ビルドモード>

# 失敗したら止める
set -euo pipefail

# このスクリプトの場所
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FLUTTER_DEVICE_ID="${1:-}" # デバイスID
BUILD_MODE="${2:-debug}" # ビルドモード

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

# 起動する
flutter run --"$BUILD_MODE" -d "$FLUTTER_DEVICE_ID"
