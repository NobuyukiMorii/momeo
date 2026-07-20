#!/usr/bin/env bash
# ============================================================
# ストア掲載用スクリーンショットの iOS 一括撮影
#
#   iPhone 16 Pro Max シミュレータ（6.9 インチ = App Store 必須サイズ、
#   1320x2868）で全シーンを撮影し、notes/release/screenshots/ios/ に保存する。
#   シーンの表示内容は lib/pages/dev/screenshot/screenshot_scenes.dart を参照。
#
#   使い方: bash scripts/take_ios_screenshots.sh
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE_NAME="iPhone 16 Pro Max"
BUNDLE_ID="jp.momeo"
APP_PATH="build/ios/iphonesimulator/Runner.app"
# simctl io screenshot は相対パスを解決できないため絶対パスにする
OUT_DIR="$PWD/notes/release/screenshots/ios"

# 撮影するシーン（保存ファイル名:シーン名。並び順はストアに載せる順）
SCENES=(
  "01_splash_auto_start:splash_auto_start"
  "02_splash_auto_stop:splash_auto_stop"
  "03_splash_open_speak_saved:splash_open_speak_saved"
  "04_listening_idle:listening_idle"
  "05_listening_first_memo:listening_first_memo"
  "06_listening_growing_memos:listening_growing_memos"
  "07_listening_memo_list:listening_memo_list"
)

# ---------------------------------
# シミュレータの起動とステータスバーの整形
# ---------------------------------
UDID=$(xcrun simctl list devices available | grep "$DEVICE_NAME (" | head -1 | grep -oE '[0-9A-F-]{36}')
if [ -z "$UDID" ]; then
  echo "エラー: シミュレータ「$DEVICE_NAME」が見つかりません" >&2
  exit 1
fi

echo "=== シミュレータを起動: $DEVICE_NAME ($UDID)"
xcrun simctl bootstatus "$UDID" -b

# ステータスバーを 9:41・電波/Wi-Fi 最大・満充電に整える
xcrun simctl status_bar "$UDID" override \
  --time "9:41" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 \
  --batteryState charged --batteryLevel 100

# ---------------------------------
# シーンごとに ビルド → 起動 → 撮影
# ---------------------------------
mkdir -p "$OUT_DIR"

for entry in "${SCENES[@]}"; do
  file="${entry%%:*}"
  scene="${entry#*:}"

  echo "=== 撮影: $scene"
  flutter build ios --simulator --debug --dart-define=SCREENSHOT_SCENE="$scene"
  xcrun simctl install "$UDID" "$APP_PATH"
  xcrun simctl launch "$UDID" "$BUNDLE_ID"

  # 波形の履歴が画面幅に行き渡り、アクティブカードの登場が終わるのを待つ
  sleep 4

  xcrun simctl io "$UDID" screenshot "$OUT_DIR/$file.png"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID"
done

echo "=== 完了: $OUT_DIR"
