# ---------------------------------
# momeo 開発用コマンド集
#
#   モデル（NeMo 625MB）の取得・配置を各コマンドの前段に挟むことで、
#   クリーンな環境・端末でも1コマンドで開発を始められるようにする。
#   各準備スクリプトは冪等（揃っていれば何もしない）なので、毎回実行してよい。
#
#   使い方:
#     make run d=<デバイスID>   # 端末を指定して実行（ID は flutter devices。指定は必須）
#     make build-ios           # モデルを揃えてから flutter build ipa
#     make build-android       # モデルを揃えてから flutter build appbundle
#     make models              # モデルのダウンロードだけ行う
# ---------------------------------

# 実行対象のデバイスID（run では必須）。例: make run d=emulator-5554
d ?=

.DEFAULT_GOAL := help

.PHONY: help models run build-ios build-android require-device

help:
	@echo "make run d=<デバイスID>  … 端末を指定してモデルを揃えてから flutter run"
	@echo "make build-ios          … モデルを揃えてから flutter build ipa"
	@echo "make build-android      … モデルを揃えてから flutter build appbundle"
	@echo "make models             … モデルのダウンロードだけ行う"

# ---------------------------------
# モデルの取得（.dev_models/ まで。端末やビルドへの配置は各スクリプトが行う）
# ---------------------------------

models:
	bash scripts/download_nemo_model.sh

# ---------------------------------
# 開発実行（端末は必ず指定させ、端末の種類の判定は各スクリプトに任せる）
# ---------------------------------
#   実機 ⇄ シミュレータ … 前の成果物が居座ると署名エラーで入らないので、切り替えたら捨てる
#   Android 端末 → place_android_device_models.sh が内部ストレージへ手置き（iOS 配置はスキップ）
#   iOS 端末     → place_ios_models.sh が ios/Runner/Models/ へ配置（手置きはスキップ）
run: require-device models
	bash scripts/clean_on_simulator_device_switch.sh $(d)
	bash scripts/place_android_device_models.sh $(d)
	bash scripts/place_ios_models.sh $(d)
	flutter run -d $(d)

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
