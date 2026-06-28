#!/usr/bin/env ruby
# frozen_string_literal: true
#
# iOS の Xcode プロジェクトに、手で足したファイルを登録するスクリプト。
#
#   2種類のファイルを、それぞれ正しいビルドフェーズに登録する:
#     1. モデル資産（model.int8.onnx / tokens.txt） → Copy Bundle Resources（同梱する資産）
#     2. ネイティブ Swift（SttModelChannel.swift）   → Compile Sources（コンパイルする）
#
#   なぜ必要か:
#     ファイルを ios/Runner/ 配下に置いただけでは Xcode は認識しない。
#     project.pbxproj に「このファイルをこのフェーズで使う」と登録して初めて、
#     ビルド時に同梱（資産）・コンパイル（ソース）される。
#     手で Xcode の GUI を操作する代わりに、xcodeproj（CocoaPods 同梱）で安全・確実に行う。
#
#   前提: モデルは先に scripts/fetch_nemo_model.sh で ios/Runner/Models/ に置いてあること。
#   使い方: ruby scripts/register_ios_files.rb
#
#   ※ 何度実行しても安全（すでに登録済みなら二重登録しない＝idempotent）。
#   ※ これは「一度きりの編集」。書き換えた project.pbxproj をコミットすれば、
#     他の人は git pull するだけで登録済みになる。

require 'xcodeproj'

# ---------------------------------
# 場所の割り出し
# ---------------------------------
SCRIPT_DIR   = __dir__
PROJECT_ROOT = File.dirname(SCRIPT_DIR)
IOS_DIR      = File.join(PROJECT_ROOT, 'ios')
PROJECT_PATH = File.join(IOS_DIR, 'Runner.xcodeproj')
RUNNER_DIR   = File.join(IOS_DIR, 'Runner')

TARGET_NAME  = 'Runner'

# 登録対象は「Runner グループからの相対パス」で書く
RESOURCE_FILES = ['Models/model.int8.onnx', 'Models/tokens.txt'].freeze # → 同梱資産
SOURCE_FILES   = ['SttModelChannel.swift'].freeze                       # → コンパイル対象

# ---------------------------------
# 事前チェック：登録するファイルが実在するか
# ---------------------------------
(RESOURCE_FILES + SOURCE_FILES).each do |relative_path|
  full_path = File.join(RUNNER_DIR, relative_path)
  next if File.exist?(full_path)

  warn "✗ #{relative_path} が見つかりません: #{full_path}"
  warn '  先に scripts/fetch_nemo_model.sh を実行したか確認してください。'
  exit 1
end

# ---------------------------------
# Xcode プロジェクトを開いて、対象（Runner）を見つける
# ---------------------------------
project = Xcodeproj::Project.open(PROJECT_PATH)

target = project.targets.find { |t| t.name == TARGET_NAME }
raise "ターゲット '#{TARGET_NAME}' が見つかりません" if target.nil?

runner_group = project.main_group[TARGET_NAME]
raise "グループ '#{TARGET_NAME}' が見つかりません" if runner_group.nil?

# ---------------------------------
# 1ファイルを「ファイル参照」＋「指定フェーズ」に登録する共通処理（二重登録しない）
#   relative_path: Runner グループからの相対パス（例 'Models/model.int8.onnx'）
#   build_phase  : 追加先のビルドフェーズ（リソース or ソース）
# ---------------------------------
def register_file(runner_group, relative_path, build_phase)
  # 親グループをたどって用意（例 'Models/x' なら Runner > Models を作る）
  *group_names, file_name = relative_path.split('/')
  group = runner_group
  group_names.each do |group_name|
    group = group[group_name] || group.new_group(group_name, group_name)
  end

  # 1) ファイル参照（無ければ作る）
  file_ref = group.files.find { |f| f.display_name == file_name }
  if file_ref.nil?
    file_ref = group.new_reference(file_name)
    puts "→ ファイル参照を追加: #{relative_path}"
  else
    puts "✓ ファイル参照は既に存在: #{relative_path}"
  end

  # 2) 指定フェーズに追加（無ければ）
  if build_phase.files.any? { |build_file| build_file.file_ref == file_ref }
    puts "✓ 登録済み: #{relative_path}"
  else
    build_phase.add_file_reference(file_ref)
    puts "→ 登録: #{relative_path}"
  end
end

# ---------------------------------
# 本体：資産はリソースへ、Swift はソースへ
# ---------------------------------
RESOURCE_FILES.each { |path| register_file(runner_group, path, target.resources_build_phase) }
SOURCE_FILES.each   { |path| register_file(runner_group, path, target.source_build_phase) }

project.save

puts
puts '完了しました。project.pbxproj を更新しました。'
