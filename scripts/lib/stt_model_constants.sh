#!/usr/bin/env bash
#
# オンデバイス STT モデル（SenseVoice Small int8）の取得元とファイル定義（各スクリプトから source して使う）。
#
#   バイト数は「途中で切れた半端なファイル」を弾く整合性チェックに使う。
#   ※ 同じバイト数を lib/stt/stt_model_provisioner.dart でも使う（端末で読む直前の
#     最終確認）。モデルを更新するときは両方直すこと。

# 置き場所（.dev_models/ 配下のフォルダ名）。版ごとに分けて、前の版を消さずに残す
readonly MODEL_SUB_DIR="sensevoice-2024-07-17"

# 取得元。sherpa-onnx の公式リリースに上がっている書庫をそのまま使う
readonly MODEL_ARCHIVE_NAME="sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2"
readonly MODEL_ARCHIVE_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$MODEL_ARCHIVE_NAME"
readonly MODEL_ARCHIVE_SHA256="7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e"

# 書庫の中から取り出す2ファイル（音声 → 番号 と、番号 → 文字）
readonly MODEL_FILE="model.int8.onnx"
readonly MODEL_EXPECTED_BYTES=239233841

readonly TOKENS_FILE="tokens.txt"
readonly TOKENS_EXPECTED_BYTES=315894
