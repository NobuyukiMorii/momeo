#!/usr/bin/env bash
# ============================================================
# サイト掲載用デモ動画の iOS 画面収録
#
#   iPhone 16 Pro Max シミュレータ（1320x2868）で収録モードのアプリを動かし、
#   疑似発話によってカードが増えていく様子を録画して docs/videos/ に書き出す。
#   発話内容は recording_listening_simulator.dart を参照。
#
#   ステータスバー（時計・電池）はアプリ側で消しているが、Dynamic Island と
#   ホームインジケーターは OS が描くため消せない。これは ffmpeg で
#   上下を切り落として取り除く。
#
#   使い方: bash scripts/take_ios_demo_video.sh
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE_NAME="iPhone 16 Pro Max"
BUNDLE_ID="jp.momeo"
APP_PATH="build/ios/iphonesimulator/Runner.app"

# 収録の生データ（大きいので build 配下に置き、リポジトリには含めない）
RAW_DIR="$PWD/build/recording"
RAW_FILE="$RAW_DIR/demo.mov"

# 書き出し先
OUT_DIR="$PWD/docs/videos"
OUT_NAME="how-it-works"

# ---------------------------------
# 時間の設定
#   動画は「待機画面 → momeo → 画面遷移 → 発話の列 → 最後の余韻」の順。
#   アプリを待機画面まで起動してから録画し、ホーム画面が入るのを防ぐ
# ---------------------------------
WAIT_AFTER_LAUNCH=1.5 # アプリの待機画面が描かれるまで
RECORD_SECONDS=21     # 録画する長さ
TRIM_START=2          # 完成動画を momeo の表示から始めるために除く冒頭部分

# ---------------------------------
# 上端から切り落とす量（1320x2868 に対する画素数）
#   Dynamic Island は 42〜151 行目を占めるので、その下まで落とす。
#   ホームインジケーターはアプリ側のシステム UI 非表示で消えるため、
#   下端は切らずに残す（カードを1枚でも多く見せる）
# ---------------------------------
CROP_TOP=156
CROP_BOTTOM=0

# 書き出す横幅（表示は約半分の幅なので、2倍の解像度を持たせる）
OUT_WIDTH=660

# ---------------------------------
# シミュレータの起動
# ---------------------------------
UDID=$(xcrun simctl list devices available | grep "$DEVICE_NAME (" | head -1 | grep -oE '[0-9A-F-]{36}')
if [ -z "$UDID" ]; then
  echo "エラー: シミュレータ「$DEVICE_NAME」が見つかりません" >&2
  exit 1
fi

echo "=== シミュレータを起動: $DEVICE_NAME ($UDID)"
xcrun simctl bootstatus "$UDID" -b

# ---------------------------------
# ビルドして起動
# ---------------------------------
echo "=== ビルド: 画面収録モード"
flutter build ios --simulator --debug --dart-define=RECORDING_MODE=true
xcrun simctl install "$UDID" "$APP_PATH"

mkdir -p "$RAW_DIR"
rm -f "$RAW_FILE"

echo "=== 起動して収録"
xcrun simctl launch "$UDID" "$BUNDLE_ID"

# アプリ側は起動後3秒間、収録開始用の待機画面を表示する
sleep "$WAIT_AFTER_LAUNCH"

xcrun simctl io "$UDID" recordVideo --codec h264 --force "$RAW_FILE" &
RECORDER_PID=$!

sleep "$RECORD_SECONDS"

# SIGINT で止めるとファイルが書き終わる（kill -9 では壊れる）
kill -INT "$RECORDER_PID"
wait "$RECORDER_PID" || true

xcrun simctl terminate "$UDID" "$BUNDLE_ID" || true

# ---------------------------------
# 仕上げ（上下を切り落として web 用に書き出す）
# ---------------------------------
mkdir -p "$OUT_DIR"

FILTER="trim=start=${TRIM_START},setpts=PTS-STARTPTS,crop=iw:ih-${CROP_TOP}-${CROP_BOTTOM}:0:${CROP_TOP},scale=${OUT_WIDTH}:-2"

echo "=== 書き出し: mp4"
ffmpeg -y -loglevel error -i "$RAW_FILE" \
  -vf "$FILTER" -an \
  -c:v libx264 -profile:v high -pix_fmt yuv420p -crf 26 \
  -movflags +faststart \
  "$OUT_DIR/$OUT_NAME.mp4"

# この素材では webm(VP9) のほうが mp4 より大きくなるため、mp4 だけにする。
# h264 はどのブラウザでも再生できる

echo "=== 完了: $OUT_DIR"
ls -lh "$OUT_DIR"
