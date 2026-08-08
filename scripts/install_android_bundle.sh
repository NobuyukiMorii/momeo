#!/usr/bin/env bash
# Google Play へ提出するビルド（AAB = Android App Bundle）を、Google Play を通さず Android 実機へ入れる。
# 使い方:bash scripts/install_android_bundle.sh <adbシリアル>
# 前提: make build-android 済み。bundletool が入っていること（brew install bundletool）

# 失敗したら止める
set -euo pipefail

# アプリの識別名。同じならアプリも同じと見なされる
readonly APP_ID="jp.momeo"

# このスクリプトの場所
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# プロジェクトの場所
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Google Play へ渡すビルド（AAB = Android App Bundle）の置き場所。このままでは端末に入らない
readonly BUNDLE_PATH="$PROJECT_ROOT/build/app/outputs/bundle/release/app-release.aab"

# 端末にそのまま入るビルド（APK = Android application package）の置き場所
readonly APKS_PATH="$PROJECT_ROOT/build/app/outputs/bundle/release/app-release.apks"

ADB_SERIAL="${1:-}" # どの端末か（adb シリアル）

# ---------------------------------
# 引数チェック: Android端末のadbシリアル
# ---------------------------------
if [ -z "$ADB_SERIAL" ]; then # 対象の端末が分からないなら
  # エラーメッセージ
  echo "✗ adb シリアルを指定してください。" >&2
  # 終了
  exit 1
fi

# ---------------------------------
# Google Play へ渡すビルド（AAB = Android App Bundle）をビルドするツール（bundletool）があるか確かめる
# ---------------------------------
if ! command -v bundletool > /dev/null 2>&1; then # ツールがないなら
  # エラーメッセージ
  echo "✗ bundletool がありません。brew install bundletool で入れてください。" >&2
  # 終了
  exit 1
fi

# ---------------------------------
# Google Play へ渡すビルド（AAB = Android App Bundle）が出来ているか確かめる
# ---------------------------------
if [ ! -f "$BUNDLE_PATH" ]; then # Google Play へ渡すビルド（AAB = Android App Bundle）がまだ無いなら
  # エラーメッセージ
  echo "✗ $BUNDLE_PATH がありません。先に make build-android を実行してください。" >&2
  # 終了
  exit 1
fi

# ---------------------------------
# Google Play へ渡すビルド（AAB = Android App Bundle）から端末向けのビルド（APK = Android application package）一式を作る
# ---------------------------------
echo "→ AAB から端末向けの APK 一式を作ります …"

# この端末で動く APK に変える（--local-testing でモデル配信も再現）
bundletool build-apks \
  --bundle="$BUNDLE_PATH" \
  --output="$APKS_PATH" \
  --overwrite \
  --local-testing

# ---------------------------------
# 既存のアプリを消してから入れる
# ---------------------------------
# 消すことを伝える
echo "→ 既存のアプリを消します …"

# 署名が違うと上書きできないので先に消す
adb -s "$ADB_SERIAL" uninstall "$APP_ID" > /dev/null 2>&1 || true

# 始まりを伝える
echo "→ 端末へインストールします（625MB を含みます）…"

# 結果を受け取る入れ物
install_status=0

# 端末へビルド（APK = Android application package）一式を入れる
bundletool install-apks --apks="$APKS_PATH" --device-id="$ADB_SERIAL" || install_status=$?

# ---------------------------------
# 本当に入ったかを確かめる
# ---------------------------------
# 端末にアプリの識別名があるかをチェック
if ! adb -s "$ADB_SERIAL" shell pm list packages "$APP_ID" 2>/dev/null \
  | tr -d '\r' | grep -q "^package:$APP_ID$"; then # 端末にアプリの識別名がないなら
  # エラー
  echo "✗ インストールに失敗しました（bundletool の終了コード: $install_status）" >&2

  # 先へ進ませない
  exit 1
fi

# 終わりを伝える
echo "✓ 本番経路のアプリを入れました"
