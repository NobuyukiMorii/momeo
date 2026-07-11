#!/usr/bin/env bash
#
# NeMo モデルを Android の fast-follow アセットパック（nemo_models モジュール）へ
# 配置するスクリプト（無ければコピーする）。
#
#   flutter build appbundle の前に実行する。AAB にはこのパックの中身が入るため、
#   ここが空のままビルドすると「モデル無し」の AAB ができてしまう。
#
#   使い方:
#     bash scripts/place_android_pack_models.sh
#
#   前提: .dev_models/ にモデルがあること（scripts/download_nemo_model.sh で取得）

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly DEV_MODELS_DIR="$PROJECT_ROOT/.dev_models"
readonly PACK_MODELS_DIR="$PROJECT_ROOT/android/nemo_models/src/main/assets/models"

# ファイル名の共通定数（MODEL_FILE / TOKENS_FILE）
source "$SCRIPT_DIR/lib/nemo_model_constants.sh"

file_size_in_bytes() {
  wc -c < "$1" | tr -d ' '
}

mkdir -p "$PACK_MODELS_DIR"

for file_name in "$MODEL_FILE" "$TOKENS_FILE"; do
  src="$DEV_MODELS_DIR/$file_name"
  dst="$PACK_MODELS_DIR/$file_name"

  if [ ! -f "$src" ]; then
    echo "✗ $src がありません。" >&2
    echo "  先に bash scripts/download_nemo_model.sh を実行してください。" >&2
    exit 1
  fi

  # すでに同じサイズで置いてあればコピーし直さない
  if [ -f "$dst" ] && [ "$(file_size_in_bytes "$dst")" = "$(file_size_in_bytes "$src")" ]; then
    echo "✓ アセットパック: $file_name は配置済み"
    continue
  fi

  echo "→ アセットパックへコピー: $file_name"
  cp "$src" "$dst"
done

echo "✓ アセットパックへの配置が完了しました: $PACK_MODELS_DIR"
