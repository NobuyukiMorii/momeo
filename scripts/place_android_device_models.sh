#!/usr/bin/env bash
#
# 開発機の Android 端末に NeMo モデルを手置きするスクリプト（無ければ入れる）。
#
#   何をするか:
#     1. 対象が Android 端末かを確かめる（iOS 端末や端末なしなら何もせず正常終了）
#     2. アプリ（jp.momeo）が未インストールなら debug ビルドを入れる
#        （手置き先がアプリの内部ストレージなので、アプリが先に必要。APK が無ければビルドもする）
#     3. 端末内のモデルのバイト数を確かめ、正しく揃っていれば何もしない
#     4. 足りなければ .dev_models/ から push して内部ストレージへコピーする
#
#   使い方:
#     bash scripts/place_android_device_models.sh [デバイスID]
#       デバイスID省略時: adb に見えている Android 端末が1台ならそれを使う
#
#   前提: .dev_models/ にモデルがあること（scripts/download_nemo_model.sh で取得）

set -euo pipefail

readonly APP_ID="jp.momeo"

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly DEV_MODELS_DIR="$PROJECT_ROOT/.dev_models"

# adb 端末まわりの共通ヘルパー（list_android_devices / resolve_adb_serial）
source "$SCRIPT_DIR/lib/adb_devices.sh"

# ファイル名と正しいバイト数の共通定数（MODEL_FILE / MODEL_EXPECTED_BYTES など）
source "$SCRIPT_DIR/lib/nemo_model_constants.sh"

# 引数のデバイスID（Flutter devices が表示する ID。省略可）
FLUTTER_DEVICE_ID="${1:-}"

# 実際に adb へ渡すシリアル。無線接続では Flutter の ID と食い違うので別に解決する
ADB_SERIAL=""

# ---------------------------------
# adb まわりの小道具
# ---------------------------------

# 解決済みのシリアルで adb を呼ぶ
run_adb() {
  adb -s "$ADB_SERIAL" "$@"
}

# ---------------------------------
# 端末内のファイルのバイト数。
# ---------------------------------
device_file_size() {
  local device_path="$1"
  run_adb shell run-as "$APP_ID" wc -c "$device_path" 2>/dev/null \
    | tr -d '\r' | awk '{print $1}' || true
}

# ---------------------------------
# 1. 対象が Android 端末かを確かめる
# ---------------------------------

if [ -n "$FLUTTER_DEVICE_ID" ]; then
  # 指定IDに対応する adb シリアルを解決。見つからなければ iOS 等とみなしスキップ
  ADB_SERIAL="$(resolve_adb_serial "$FLUTTER_DEVICE_ID" || true)"
  if [ -z "$ADB_SERIAL" ]; then
    echo "· $FLUTTER_DEVICE_ID は Android 端末として見つからないため、モデルの手置きはスキップします"
    exit 0
  fi
else
  android_devices="$(list_android_devices)"
  device_count="$(echo "$android_devices" | grep -c . || true)"
  if [ "$device_count" -eq 0 ]; then
    echo "· Android 端末が見つからないため、モデルの手置きはスキップします"
    exit 0
  fi
  if [ "$device_count" -gt 1 ]; then
    echo "✗ Android 端末が複数あります。d=<デバイスID> で対象を指定してください:" >&2
    echo "$android_devices" >&2
    exit 1
  fi
  ADB_SERIAL="$android_devices"
fi

echo "対象の Android 端末: $ADB_SERIAL"

# ---------------------------------
# 2. 手元（.dev_models/）にモデルが揃っているか確かめる
# ---------------------------------

for file_name in "$MODEL_FILE" "$TOKENS_FILE"; do
  if [ ! -f "$DEV_MODELS_DIR/$file_name" ]; then
    echo "✗ $DEV_MODELS_DIR/$file_name がありません。" >&2
    echo "  先に bash scripts/download_nemo_model.sh を実行してください。" >&2
    exit 1
  fi
done

# ---------------------------------
# 3. アプリが未インストールなら debug ビルドを入れる
# ---------------------------------

# run-as が通る = debug ビルドのアプリが入っている
if ! run_adb shell run-as "$APP_ID" sh -c 'true' >/dev/null 2>&1; then
  echo "→ アプリが未インストールのため、debug ビルドをインストールします …"

  # flutter install はビルドしないため、APK が無い（flutter clean 直後など）なら先にビルドする
  debug_apk="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-debug.apk"
  if [ ! -f "$debug_apk" ]; then
    echo "→ debug APK が無いため、先にビルドします …"
    (cd "$PROJECT_ROOT" && flutter build apk --debug)
  fi

  # flutter へ渡す ID。無線接続の adb シリアルは mDNS 接尾辞を剥がすと Flutter の表示 ID になる
  flutter_device_id="${FLUTTER_DEVICE_ID:-${ADB_SERIAL%._adb-tls-connect._tcp.}}"
  (cd "$PROJECT_ROOT" && flutter install --debug -d "$flutter_device_id")
fi

# ---------------------------------
# 4. 端末内のモデルを確かめ、足りなければ push する
# ---------------------------------

model_ok=true
if [ "$(device_file_size "files/models/$MODEL_FILE")" != "$MODEL_EXPECTED_BYTES" ]; then
  model_ok=false
fi
if [ "$(device_file_size "files/models/$TOKENS_FILE")" != "$TOKENS_EXPECTED_BYTES" ]; then
  model_ok=false
fi

if [ "$model_ok" = true ]; then
  echo "✓ 端末にモデルは配置済みです（何もしません）"
  exit 0
fi

# 内部ストレージには直接 push できないので、/data/local/tmp を中継する
echo "→ モデルを端末へ push します（625MB のため数分かかることがあります）…"
run_adb push "$DEV_MODELS_DIR/$MODEL_FILE" /data/local/tmp/
run_adb push "$DEV_MODELS_DIR/$TOKENS_FILE" /data/local/tmp/
run_adb shell chmod 644 "/data/local/tmp/$MODEL_FILE" "/data/local/tmp/$TOKENS_FILE"

echo "→ アプリの内部ストレージへコピーします …"
run_adb shell run-as "$APP_ID" mkdir -p files/models
run_adb shell run-as "$APP_ID" cp "/data/local/tmp/$MODEL_FILE" files/models/
run_adb shell run-as "$APP_ID" cp "/data/local/tmp/$TOKENS_FILE" files/models/

# 中継地点の 625MB を残さない
run_adb shell rm -f "/data/local/tmp/$MODEL_FILE" "/data/local/tmp/$TOKENS_FILE"

# コピー後にもう一度バイト数を確かめる
if [ "$(device_file_size "files/models/$MODEL_FILE")" != "$MODEL_EXPECTED_BYTES" ] \
  || [ "$(device_file_size "files/models/$TOKENS_FILE")" != "$TOKENS_EXPECTED_BYTES" ]; then
  echo "✗ コピー後のバイト数が一致しません。もう一度このスクリプトを実行してください。" >&2
  exit 1
fi

echo "✓ 端末へのモデル配置が完了しました"
