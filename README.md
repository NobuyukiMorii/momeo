# momeo

音声を記録・管理するメモアプリ。

## 概要

- 音声メモの保存
- 音声メモの一覧表示
- マイク・音声認識の設定

## 開発環境での起動

```bash
flutter pub get
make run d=<デバイスID>   # 起動（ID は flutter devices で確認。指定必須）
```

STT モデル（約625MB・Git 管理外）の取得と端末への配置は `make run` が自動で行う（冪等）。

- iOS はアプリに同梱、Android は端末へ `adb push`（アンインストールで消える → 再度 `make run`）
- 本番ビルド: `make build-ios` / `make build-android`
- 詳細: `notes/on_device_stt/model_distribution.md`

## ドキュメント

本プロジェクトの仕様書および関連ドキュメントは `notes/` ディレクトリに集約されています。