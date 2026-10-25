# ---------------------------------
# momeo 開発用コマンド集
#
#   使い方:
#     make run d=<デバイスID>          # ふだんの開発はこれ（ID は flutter devices。指定は必須）
#     make run d=<ID> mode=profile     # 動きが遅くないか確かめる（本番の速さで動く）
#     make run d=<ID> mode=release     # ストアに出す前の最終確認
#     make build-ios           # flutter build ipa
#     make build-android       # flutter build appbundle
# ---------------------------------

# 実行対象のデバイスID（run では必須）。例: make run d=emulator-5554
d ?=

# 実行モード。debug / profile / release を受け付ける。例: make run d=<ID> mode=release
mode ?= debug

.DEFAULT_GOAL := help

.PHONY: help run build-ios build-android require-device

help:
	@echo "make run d=<デバイスID>           … ふだんの開発はこれ"
	@echo "make run d=<ID> mode=profile      … 動きが遅くないか確かめる（本番の速さで動く）"
	@echo "make run d=<ID> mode=release      … ストアに出す前の最終確認"
	@echo "make build-ios                    … flutter build ipa"
	@echo "make build-android                … flutter build appbundle"

# ---------------------------------
# 開発実行（端末は必ず指定させ、端末とモードによる分岐はスクリプトに任せる）
# ---------------------------------
run: require-device
	bash scripts/run_on_device.sh $(d) $(mode)

# ---- 対象の取り違えを避けるため、ビルドより前に即エラーで止める
require-device:
	@if [ -z "$(strip $(d))" ]; then \
	  echo "エラー: d=<デバイスID> を指定してください。例: make run d=<ID>（ID は flutter devices で確認）" >&2; \
	  exit 1; \
	fi

# ---------------------------------
# 本番ビルド（ビルド番号はエポック分で自動採番）
# ---------------------------------
#   ストアが要求する単調増加を人手なしで満たすため → notes/release/versioning/version_management.md

# ---- iOS
build-ios:
	flutter build ipa --build-number=$$(( $$(date +%s) / 60 ))

# ---- Android
build-android:
	flutter build appbundle --build-number=$$(( $$(date +%s) / 60 ))
