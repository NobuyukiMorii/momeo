# momeo

音声を記録・管理するメモアプリ。

## 概要

- 音声メモの保存
- 音声メモの一覧表示
- マイク・音声認識の設定

## ドキュメント

本プロジェクトの仕様書および関連ドキュメントは `docs/` ディレクトリに集約されています。

### デザイン仕様 (`docs/design/`)
Figma APIから抽出した「純粋な事実データ（数値・構成）」を、Flutterの実装にそのまま直結する形で構造化して整理しています。

* **`00_raw_assets/`**: Figma APIの生データ・参考スクリーンショット群
* **`01_system_tokens/`**: カラー・タイポグラフィ・余白などのシステム定数（トークン）
* **`02_components/`**: 再利用可能なUIコンポーネントの構造および数値事実
* **`03_screen_states/`**: 実装する画面状態（State）ごとの全体構成レシピカタログ

> **Figma原本**: https://www.figma.com/design/ErddJebG6AfGqaGTCKfDuk/momery
