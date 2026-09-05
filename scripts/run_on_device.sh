#!/usr/bin/env bash
# 端末とビルドモードに応じて、アプリをビルドして動かす。
# 使い方:bash scripts/run_on_device.sh <デバイスID> <ビルドモード>

# 失敗したら止める
set -euo pipefail

# アプリの識別名。起動をかけるときに指す
readonly APP_ID="jp.momeo"

# このスクリプトの場所
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# プロジェクトの場所
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# adb 端末まわりのヘルパー
source "$SCRIPT_DIR/lib/adb_devices.sh"

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
# 対象が Android 端末かを見る
# ---------------------------------
ADB_SERIAL="$(resolve_adb_serial "$FLUTTER_DEVICE_ID" || true)"

# ---------------------------------
# Android の release は本番経路で動かす
# ---------------------------------
if [ -n "$ADB_SERIAL" ] && [ "$BUILD_MODE" = "release" ]; then # Android端末でreleaseビルドするなら
  # 始まりを伝える
  echo "→ 本番と同じ AAB を作ります …"

  # Google Play へ渡す形（AAB = Android App Bundle）を作る。モデルもこの中に入る
  make -C "$PROJECT_ROOT" build-android

  # AAB を、端末に入る形（APK = Android application package）に変えて入れる
  bash "$SCRIPT_DIR/install_android_bundle.sh" "$ADB_SERIAL"

  # 起動を伝える
  echo "→ アプリを起動します …"

  # ランチャーのアイコンを押すのと同じ起動をかける
  adb -s "$ADB_SERIAL" shell am start -n "$APP_ID/.MainActivity" > /dev/null

  # ログの見方を案内する
  echo "✓ 本番経路で起動しました"
  echo "  ログを見るなら: adb -s $ADB_SERIAL logcat -s sherpa-onnx"
  exit 0
fi

# ---------------------------------
# Android の release 以外は flutter run
# ---------------------------------
# 前回の iOS ビルドの残骸が残っていたらクリーンする
bash "$SCRIPT_DIR/clean_stale_ios_build.sh" "$FLUTTER_DEVICE_ID"

# Android のモデルを置く
bash "$SCRIPT_DIR/place_android_device_models.sh" "$FLUTTER_DEVICE_ID"

# iOS のモデルを置く
bash "$SCRIPT_DIR/place_ios_models.sh" "$FLUTTER_DEVICE_ID"

# 起動する
flutter run --"$BUILD_MODE" -d "$FLUTTER_DEVICE_ID"
