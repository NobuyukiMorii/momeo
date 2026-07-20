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

# NeMo を .dev_models/ へダウンロードする（配置は端末・ビルドごとの各スクリプトが行う）
models:
	bash scripts/download_nemo_model.sh

# 開発実行。端末は必ず指定させ、OS の判定は各配置スクリプトに任せる
#   Android 端末 → place_android_device_models.sh が内部ストレージへ手置き（iOS 配置はスキップ）
#   iOS 端末     → place_ios_models.sh が ios/Runner/Models/ へ配置（手置きはスキップ）
run: require-device models
	bash scripts/place_android_device_models.sh $(d)
	bash scripts/place_ios_models.sh $(d)
	flutter run -d $(d)

# run の前提: d=<デバイスID> が無ければ、モデル取得より前に即エラーで止める
#   （複数台つなぐ環境で対象を取り違えたり無駄な処理を走らせたりしないため）
require-device:
	@if [ -z "$(strip $(d))" ]; then \
	  echo "エラー: d=<デバイスID> を指定してください。例: make run d=<ID>（ID は flutter devices で確認）" >&2; \
	  exit 1; \
	fi

# 本番ビルドのビルド番号はエポック分（1970年からの経過分数）で自動採番する。
# ストアが要求する単調増加を人手なしで満たすため。詳細: notes/release/versioning/version_management.md
# iOS の本番ビルド（モデルはバンドルリソースとして同梱される）
build-ios: models
	bash scripts/place_ios_models.sh
	flutter build ipa --build-number=$$(( $$(date +%s) / 60 ))

# Android の本番ビルド（モデルは fast-follow アセットパックに入れて AAB 化する）
build-android: models
	bash scripts/place_android_pack_models.sh
	flutter build appbundle --build-number=$$(( $$(date +%s) / 60 ))
