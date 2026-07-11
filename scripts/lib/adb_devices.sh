#!/usr/bin/env bash
#
# adb 端末まわりの共通ヘルパー（各スクリプトから source して使う）。
#
#   使い方:
#     source "$SCRIPT_DIR/lib/adb_devices.sh"

# ---------------------------------
# android の端末一覧
# ---------------------------------
# adb に「device 状態」で見えている端末のシリアル一覧を返す
list_android_devices() {
  adb devices 2>/dev/null | awk 'NR > 1 && $2 == "device" { print $1 }'
}

# ---------------------------------
# Flutter のデバイスID から adb シリアルを解決
# ---------------------------------
#   見つかればシリアルを出力して成功、見つからなければ失敗を返す。
#   「Android 端末かどうか」の判定にもこの成否をそのまま使える。
#   無線接続では Flutter は "adb-XXXX-YYYY" と短く表示するが、adb devices は
#   "adb-XXXX-YYYY._adb-tls-connect._tcp." と接尾辞付きで並ぶため、前方一致で拾う
resolve_adb_serial() {
  local wanted="$1"
  local serial
  for serial in $(list_android_devices); do
    case "$serial" in
      "$wanted" | "$wanted".*) echo "$serial"; return 0 ;;
    esac
  done
  return 1
}
