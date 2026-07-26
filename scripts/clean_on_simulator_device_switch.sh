#!/usr/bin/env bash
#
# 実機とシミュレータを行き来したとき、flutter clean を挟むスクリプト。
#
#   両者はビルドの中身が別物なのに、置き場所はどちらも build/。切り替えても増分ビルドが
#   「もうある」と誤判定して前の成果物を使い回し、実機が不正な署名とみなして弾く（0xe8008014）。
#   Android は巻き込まれないので、iOS 同士の切り替えだけを見る。
#
#   捨てると次はフルビルドになる。打ち間違いでそれを強いないよう、iOS と分かった端末だけを相手にする。
#   見ているのは make run の履歴なので、Xcode から直接起動した分までは追えない。
#
#   使い方:
#     bash scripts/clean_on_simulator_device_switch.sh <デバイスID>

set -euo pipefail

# ---- どこから呼ばれても動くよう、スクリプト自身の位置からプロジェクトを辿る
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly BUILD_DIR="$PROJECT_ROOT/build"

# ---- 前回の記録先。build/ の中に置くと、flutter clean 済みと記録なしが自然に一致する
readonly LAST_IOS_KIND_FILE="$BUILD_DIR/.last_ios_kind"

# ---- adb 端末まわりの共通ヘルパー（list_android_devices / resolve_adb_serial）
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
# 端末一覧のテキストに「(デバイスID)」が載っているか
# ---------------------------------
device_list_contains() {
  # ---- 調べる相手の一覧（simctl や xctrace の出力）
  local device_list="$1"

  # ---- その中から探すデバイスID
  local device_id="$2"

  # ---- どの一覧も「名前 (ID)」の形で並ぶので、丸括弧ごと照合すれば部分一致で誤爆しない
  case "$device_list" in
    *"($device_id)"*) return 0 ;;
  esac

  # ---- 見つからなければ失敗。呼び出し側は if の成否でそのまま分岐できる
  return 1
}

# ---------------------------------
# つないである iOS 実機の一覧（オフラインの端末は数えない）
# ---------------------------------
list_connected_ios_devices() {
  xcrun xctrace list devices 2>/dev/null \
    | awk '/^== Devices ==$/ { in_connected = 1; next } /^== / { in_connected = 0 } in_connected'
}

# ---------------------------------
# 端末の種類（どこにも見当たらなければ unknown。決め打ちで実機とみなさない）
# ---------------------------------
detect_device_kind() {
  # ---- flutter devices が表示するデバイスID
  local device_id="$1"

  # ---- adb に見えれば Android
  if resolve_adb_serial "$device_id" >/dev/null; then
    echo "android"
    return
  fi

  # ---- simctl に並んでいればシミュレータ
  if device_list_contains "$(xcrun simctl list devices 2>/dev/null)" "$device_id"; then
    echo "ios-simulator"
    return
  fi

  # ---- 最後に実機。xctrace は数秒かかるので、速い判定を試したあとに置く
  if device_list_contains "$(list_connected_ios_devices)" "$device_id"; then
    echo "ios-device"
    return
  fi

  echo "unknown"
}

# ---------------------------------
# 1. iOS と分かった端末以外は、記録にも build/ にも触らずに抜ける
# ---------------------------------

# ---- 以降の判断は、すべてこの種類だけを材料にする
current_device_kind="$(detect_device_kind "$FLUTTER_DEVICE_ID")"

# ---- Android は build/ の iOS 側と衝突しないので、記録を素通りさせる
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
# 2. 前回の iOS と違えば捨てる（記録の無い build/ も素性が分からないので捨てる）
# ---------------------------------

# ---- 記録が無いときは「記録なし」を入れて、必ず違うと判定させる
previous_device_kind="$(cat "$LAST_IOS_KIND_FILE" 2>/dev/null || echo "記録なし")"

# ---- build/ がまだ無ければ、そもそも持ち越す成果物が無い
if [ -d "$BUILD_DIR" ] && [ "$previous_device_kind" != "$current_device_kind" ]; then
  echo "→ 前回は $previous_device_kind、今回は $current_device_kind のため flutter clean します …"
  (cd "$PROJECT_ROOT" && flutter clean)
else
  echo "✓ そのままビルドします（$current_device_kind）"
fi

# ---------------------------------
# 3. 今回の iOS を記録する
# ---------------------------------

# ---- clean した直後は build/ ごと消えているので作り直す
mkdir -p "$BUILD_DIR"

# ---- 次に走らせたときの比較材料
echo "$current_device_kind" > "$LAST_IOS_KIND_FILE"
