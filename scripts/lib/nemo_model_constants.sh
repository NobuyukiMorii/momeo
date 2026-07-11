#!/usr/bin/env bash
#
# NeMo モデルのファイル名と期待バイト数の共通定数（各スクリプトから source して使う）。
#
#   バイト数は「途中で切れた半端なファイル」を弾く整合性チェックに使う。
#   ※ 同じバイト数を lib/stt/stt_model_provisioner.dart でも使う（端末で読む直前の
#     最終確認）。モデルを更新するときは両方直すこと。

readonly MODEL_FILE="model.int8.onnx"
readonly MODEL_EXPECTED_BYTES=655542604

readonly TOKENS_FILE="tokens.txt"
readonly TOKENS_EXPECTED_BYTES=28557
