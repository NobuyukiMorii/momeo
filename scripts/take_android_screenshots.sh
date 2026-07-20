#!/usr/bin/env bash
# ============================================================
# ストア掲載用スクリーンショットの Android 一括撮影
#
#   起動中のエミュレータ（なければ Pixel_10 AVD を起動）で全シーンを撮影し、
#   notes/release/screenshots/android/ に保存する。
#   シーンの表示内容は lib/pages/dev/screenshot/screenshot_scenes.dart を参照。
#
#   使い方: bash scripts/take_android_screenshots.sh
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

AVD_NAME="Pixel_10"
APP_ID="jp.momeo"
APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
OUT_DIR="notes/release/screenshots/android"

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
# エミュレータの起動を確認（なければ AVD を起動して待つ）
# 実機が同時につながっていても対象を取り違えないよう、以降は必ずシリアル指定で操作する
# ---------------------------------
if ! adb devices | grep -q "^emulator-"; then
  # emulator コマンドは PATH に無いことが多いため、SDK の既定位置から解決する
  EMULATOR_BIN="${ANDROID_HOME:-$HOME/Library/Android/sdk}/emulator/emulator"
  echo "=== エミュレータを起動: $AVD_NAME"
  nohup "$EMULATOR_BIN" -avd "$AVD_NAME" >/dev/null 2>&1 &
fi

# エミュレータが adb に現れるのを待ってシリアルを取得する
SERIAL=""
until [ -n "$SERIAL" ]; do
  SERIAL=$(adb devices | awk '/^emulator-/{print $1; exit}')
  [ -n "$SERIAL" ] || sleep 2
done
echo "=== 撮影対象: $SERIAL"

# ホーム画面まで起動し切るのを待つ
until [ "$(adb -s "$SERIAL" shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do
  sleep 2
done

# ---------------------------------
# ステータスバーをデモモードで整える（9:41・電波/Wi-Fi 最大・満充電・通知なし）
# ---------------------------------
adb -s "$SERIAL" shell settings put global sysui_demo_allowed 1
adb -s "$SERIAL" shell am broadcast -a com.android.systemui.demo -e command enter
adb -s "$SERIAL" shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941
adb -s "$SERIAL" shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false
adb -s "$SERIAL" shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4 -e fully true
adb -s "$SERIAL" shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false
adb -s "$SERIAL" shell am broadcast -a com.android.systemui.demo -e command status -e volume hide -e bluetooth hide -e location hide -e alarm hide -e sync hide -e mute hide -e speakerphone hide

# ---------------------------------
# シーンごとに ビルド → 起動 → 撮影
# ---------------------------------
mkdir -p "$OUT_DIR"

for entry in "${SCENES[@]}"; do
  file="${entry%%:*}"
  scene="${entry#*:}"

  echo "=== 撮影: $scene"
  flutter build apk --debug --dart-define=SCREENSHOT_SCENE="$scene"
  adb -s "$SERIAL" install -r "$APK_PATH"

  # 起動を検知できるよう logcat を空にしてから起動する
  adb -s "$SERIAL" logcat -c
  adb -s "$SERIAL" shell am start -n "$APP_ID/.MainActivity"

  # Flutter の初回フレーム描画（Displayed ログ）を最大60秒待つ
  # （debug ビルドのコールドスタートは10秒を超えることがある）
  for _ in $(seq 1 30); do
    if adb -s "$SERIAL" logcat -d ActivityTaskManager:I '*:S' | grep -q "Displayed $APP_ID"; then
      break
    fi
    sleep 2
  done

  # 波形の履歴が画面幅に行き渡り、アクティブカードの登場が終わるのを待つ
  sleep 4

  adb -s "$SERIAL" exec-out screencap -p > "$OUT_DIR/$file.png"
  adb -s "$SERIAL" shell am force-stop "$APP_ID"
done

# ステータスバーのデモモードを解除して元に戻す
adb -s "$SERIAL" shell am broadcast -a com.android.systemui.demo -e command exit

echo "=== 完了: $OUT_DIR"
