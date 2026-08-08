# ---------------------------------
# momeo 開発用コマンド集
#
#   モデル（NeMo 625MB）の取得・配置を各コマンドの前段に挟むことで、
#   クリーンな環境・端末でも1コマンドで開発を始められるようにする。
#   各準備スクリプトは冪等（揃っていれば何もしない）なので、毎回実行してよい。
#
#   使い方:
#     make run d=<デバイスID>          # ふだんの開発はこれ（ID は flutter devices。指定は必須）
#     make run d=<ID> mode=profile     # 動きが遅くないか確かめる（本番の速さで動く）
#     make run d=<ID> mode=release     # ストアに出す前の最終確認
#     make build-ios           # モデルを揃えてから flutter build ipa
#     make build-android       # モデルを揃えてから flutter build appbundle
#     make models              # モデルのダウンロードだけ行う
# ---------------------------------

# 実行対象のデバイスID（run では必須）。例: make run d=emulator-5554
d ?=

# 実行モード。debug / profile / release を受け付ける。例: make run d=<ID> mode=release
mode ?= debug

.DEFAULT_GOAL := help

.PHONY: help models run build-ios build-android require-device

help:
	@echo "make run d=<デバイスID>           … ふだんの開発はこれ"
	@echo "make run d=<ID> mode=profile      … 動きが遅くないか確かめる（本番の速さで動く）"
	@echo "make run d=<ID> mode=release      … ストアに出す前の最終確認"
	@echo "make build-ios                    … モデルを揃えてから flutter build ipa"
	@echo "make build-android                … モデルを揃えてから flutter build appbundle"
	@echo "make models                       … モデルのダウンロードだけ行う"

# ---------------------------------
# モデルの取得（.dev_models/ まで。端末やビルドへの配置は各スクリプトが行う）
# ---------------------------------

models:
	bash scripts/download_nemo_model.sh

# ---------------------------------
# 開発実行（端末は必ず指定させ、端末とモードによる分岐はスクリプトに任せる）
# ---------------------------------
run: require-device models
	bash scripts/run_on_device.sh $(d) $(mode)

# ---- 対象の取り違えと無駄な処理を避けるため、モデル取得より前に即エラーで止める
require-device:
	@if [ -z "$(strip $(d))" ]; then \
	  echo "エラー: d=<デバイスID> を指定してください。例: make run d=<ID>（ID は flutter devices で確認）" >&2; \
	  exit 1; \
	fi

# ---------------------------------
# 本番ビルド（ビルド番号はエポック分で自動採番）
# ---------------------------------
#   ストアが要求する単調増加を人手なしで満たすため → notes/release/versioning/version_management.md

# ---- iOS: モデルはバンドルリソースとして同梱する
build-ios: models
	bash scripts/place_ios_models.sh
	flutter build ipa --build-number=$$(( $$(date +%s) / 60 ))

# ---- Android: モデルは fast-follow アセットパックに入れて AAB 化する
build-android: models
	bash scripts/place_android_pack_models.sh
	flutter build appbundle --build-number=$$(( $$(date +%s) / 60 ))
