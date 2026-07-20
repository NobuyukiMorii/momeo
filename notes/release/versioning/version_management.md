# バージョン管理の方針と実装

momeo のバージョン運用ルールと、ビルド番号自動化の実装内容をまとめる。

## 決定事項

- 初回リリースは **1.0.0** で出す
- バージョン名（1.0.0 の部分）は `pubspec.yaml` の `version:` だけで管理する
- ビルド番号（versionCode / CFBundleVersion）は**エポック分方式で全自動**にし、人間は一切意識しない

## バージョンの仕組み（前提知識）

`pubspec.yaml` の `version: 1.0.0+1` は「+ の前 = バージョン名」「+ の後 = ビルド番号」。
Flutter がビルド時に両OSへ次のように流し込む。

| pubspec | iOS | Android |
|---|---|---|
| `1.0.0` | CFBundleShortVersionString（表示バージョン） | versionName |
| `+1` | CFBundleVersion（ビルド番号） | versionCode |

- iOS 側: `ios/Runner/Info.plist` が `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)` を参照
- Android 側: `android/app/build.gradle.kts` が `flutter.versionName` / `flutter.versionCode` を参照
- つまり **Xcode も AndroidManifest も build.gradle も触らない**。編集するのは pubspec のみ

## ストア側の制約（ビルド番号が必要な理由）

- **Google Play**: AAB をアップロードするたびに versionCode が過去のどのアップロードよりも
  大きいことが必須。同じ値は内部テストトラックでも再利用不可。上限は 21 億
- **App Store**: 同じバージョン名で複数ビルドを上げる場合（審査リジェクト後の再提出など）、
  ビルド番号が一意であることが必須
- `version: 1.0.0`（+なし）にすると Android の versionCode が常に 1 になり、
  2 回目のアップロードができなくなるため不可

## 実装内容: ビルド番号の自動化

`Makefile` の `build-ios` / `build-android` に `--build-number` を付け、
**エポック分（1970-01-01 からの経過分数）**をビルド番号にする。

```makefile
build-ios: models
	bash scripts/place_ios_models.sh
	flutter build ipa --build-number=$$(( $$(date +%s) / 60 ))

build-android: models
	bash scripts/place_android_pack_models.sh
	flutter build appbundle --build-number=$$(( $$(date +%s) / 60 ))
```

- `--build-number` はビルド時に pubspec の `+N` を上書きするだけ。pubspec は `+1` のまま据え置く
- ビルドするたびに値が勝手に増えるため、versionCode の単調増加が自動的に満たされる

### エポック分を選ぶ理由

| 方式 | 判定 | 理由 |
|---|---|---|
| エポック秒（`date +%s`） | ✗ | Play の上限 21 億に 2036 年に到達する |
| `YYYYMMDDHHMM` 形式 | ✗ | 桁が多すぎて 21 億を超え、そもそも使えない |
| **エポック分（秒 ÷ 60）** | ✓ | 現在約 3,000 万で上限まで実質無限。分単位で一意 |

唯一の弱点は「同じ 1 分以内に 2 回ビルドすると同じ番号になる」ことだが、
モデル配置を含むビルドが 1 分以内に 2 回完了することは実用上ない。

## リリース時の作業フロー

1. `pubspec.yaml` の `version:` を上げる（例: `1.0.0+1` → `1.0.1+1`。`+1` は触らない）
2. `make build-ios` / `make build-android` でビルド（ビルド番号は自動採番）
3. ストアへアップロード

バージョン名の上げ方の目安:

- **z を上げる（1.0.1）**: バグ修正のみ
- **y を上げる（1.1.0）**: 機能追加
- **x を上げる（2.0.0）**: 大きな刷新

## 注意点

- `flutter run` や普段の開発ビルドには影響しない（Makefile のリリースビルドだけの話）
- 審査リジェクト後の再提出も「もう一度 make するだけ」で新しいビルド番号になる
- iOS のビルド番号もエポック分になるため桁が大きいが、Apple 側に上限はなく問題ない
