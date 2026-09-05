#!/usr/bin/env bash
#
# iOS のビルドに使い回せない成果物が残っていたら、flutter clean を挟むスクリプト。
#
#   実機とシミュレータ、署名ありと署名なしは、ビルドの中身が別物なのに置き場所はどれも
#   build/native_assets/ios/ で共通になっている。Flutter の増分ビルドはこの違いを見ずに
#   「もうある」と判定して前の成果物を使い回し、実機が不正な署名とみなして弾く（0xe8008014）。
#
#   履歴ではなく、今 build/native_assets/ios/ にある成果物そのものを検査する。
#   そのため make run 以外の経路（Xcode、flutter build ios --no-codesign、Claude の確認ビルドなど）で
#   作られた成果物も同じように拾える。
#
#   build/native_assets だけ消しても .dart_tool/flutter_build/ のキャッシュが残って再生成されないので、
#   掃除は flutter clean に統一する。
#
#   使い方:
#     bash scripts/clean_stale_ios_build.sh <デバイスID>

set -euo pipefail

# ---- どこから呼ばれても動くよう、スクリプト自身の位置からプロジェクトを辿る
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# ---- 検査する場所。Flutter が native assets（objective_c、sqlite3 など）のフレームワークを置く
readonly NATIVE_ASSETS_DIR="$PROJECT_ROOT/build/native_assets/ios"

# ---- Mach-O の LC_BUILD_VERSION が示す platform 番号
readonly PLATFORM_IOS_DEVICE="2"
readonly PLATFORM_IOS_SIMULATOR="7"

# ---- adb 端末まわりの共通ヘルパー（resolve_adb_serial）
source "$SCRIPT_DIR/lib/adb_devices.sh"

FLUTTER_DEVICE_ID="${1:-}"

# ---------------------------------
# 相手の端末が決まらなければ何も判断できないので、ここで止める
# ---------------------------------
if [ -z "$FLUTTER_DEVICE_ID" ]; then
  echo "✗ デバイスIDを指定してください。" >&2
  exit 1
fi

# ---------------------------------
# 端末の種類（android / ios-simulator / ios-device / unknown）
# ---------------------------------
#   flutter devices --machine の JSON から引く。xctrace は無線接続の実機を Offline に載せて
#   取りこぼすことがあるが、flutter run -d で使える端末なら必ずここに出る
detect_device_kind() {
  # ---- flutter devices が表示するデバイスID
  local device_id="$1"

  # ---- adb に見えれば Android。無線接続の短い ID もヘルパー側で吸収する
  if resolve_adb_serial "$device_id" >/dev/null; then
    echo "android"
    return
  fi

  # ---- flutter devices の一覧から、ID が一致する端末の種類を引く
  flutter devices --machine 2>/dev/null | python3 -c '
import json
import sys

wanted_device_id = sys.argv[1]
for device in json.load(sys.stdin):
    if device["id"] != wanted_device_id:
        continue
    if not device["targetPlatform"].startswith("ios"):
        print("unknown")
    elif device["emulator"]:
        print("ios-simulator")
    else:
        print("ios-device")
    break
else:
    print("unknown")
' "$device_id"
}

# ---------------------------------
# バイナリが実機向けかシミュレータ向けか（platform 番号。読めなければ空）
# ---------------------------------
detect_binary_platform() {
  # ---- 調べる Mach-O バイナリ
  local binary_path="$1"

  otool -l "$binary_path" 2>/dev/null \
    | awk '/LC_BUILD_VERSION/ { in_build_version = 1; next } in_build_version && /platform/ { print $2; exit }'
}

# ---------------------------------
# バイナリの署名が adhoc（証明書なし）か
# ---------------------------------
is_adhoc_signed() {
  # ---- 調べる Mach-O バイナリ
  local binary_path="$1"

  codesign -dv "$binary_path" 2>&1 | grep -q "^Signature=adhoc$"
}

# ---------------------------------
# 今ある成果物を、今回の端末で使い回せない理由（使い回せるなら空）
# ---------------------------------
find_stale_reason() {
  # ---- 今回ビルドする端末の種類
  local device_kind="$1"

  # ---- フレームワークごとに調べる
  local framework_dir
  for framework_dir in "$NATIVE_ASSETS_DIR"/*.framework; do
    # ---- glob が何にも当たらなければ調べる物がない
    [ -d "$framework_dir" ] || continue

    # ---- Foo.framework/Foo がバイナリ本体
    local framework_name
    framework_name="$(basename "$framework_dir" .framework)"
    local binary_path="$framework_dir/$framework_name"
    [ -f "$binary_path" ] || continue

    local binary_platform
    binary_platform="$(detect_binary_platform "$binary_path")"

    # ---- 実機向けのビルドに、シミュレータ向けや署名なしの成果物は使えない
    if [ "$device_kind" = "ios-device" ]; then
      if [ "$binary_platform" = "$PLATFORM_IOS_SIMULATOR" ]; then
        echo "$framework_name がシミュレータ向け"
        return
      fi
      if is_adhoc_signed "$binary_path"; then
        echo "$framework_name が署名なし（--no-codesign などのビルド）"
        return
      fi
    fi

    # ---- シミュレータ向けのビルドに、実機向けの成果物は使えない
    if [ "$device_kind" = "ios-simulator" ]; then
      if [ "$binary_platform" = "$PLATFORM_IOS_DEVICE" ]; then
        echo "$framework_name が実機向け"
        return
      fi
    fi
  done
}

# ---------------------------------
# 1. iOS と分かった端末以外は、build/ に触らずに抜ける
# ---------------------------------

# ---- 以降の判断は、すべてこの種類だけを材料にする
current_device_kind="$(detect_device_kind "$FLUTTER_DEVICE_ID")"

# ---- Android は build/ の iOS 側と衝突しない
if [ "$current_device_kind" = "android" ]; then
  echo "· $FLUTTER_DEVICE_ID は Android 端末のため、そのままビルドします"
  exit 0
fi

# ---- 打ち間違いかもしれない。素性が分からない相手のために成果物は捨てない
if [ "$current_device_kind" = "unknown" ]; then
  echo "· $FLUTTER_DEVICE_ID は端末一覧に見当たらないため、何もしません（ID は flutter devices で確認）"
  exit 0
fi

# ---------------------------------
# 2. 使い回せない成果物が残っていれば捨てる
# ---------------------------------

# ---- まだ一度もビルドしていなければ、持ち越す成果物が無い
if [ ! -d "$NATIVE_ASSETS_DIR" ]; then
  echo "✓ そのままビルドします（${current_device_kind}、前回の成果物なし）"
  exit 0
fi

stale_reason="$(find_stale_reason "$current_device_kind")"

if [ -n "$stale_reason" ]; then
  echo "→ 前回の成果物は ${stale_reason}のため、${current_device_kind} 向けに flutter clean します …"
  (cd "$PROJECT_ROOT" && flutter clean)
else
  echo "✓ そのままビルドします（${current_device_kind}）"
fi
