# Voice Card

## 概要
標準的なテキストを含むカードコンポーネント。

## 🎨 構造と事実データ
* **適用レイアウトトークン**:
  * padding (四方すべて): `spacing-l`
  * 子要素間Gap: `spacing-l`
  * 角丸: `radius-l`
* **適用カラートークン**:
  * 背景色: `Surface`

## 📏 伸縮ルール (Sizing & Constraints)
* **カード全体**: 横幅は原則 `Hug` だが、事実情報としてルートに幅指定 (`Fixed` / 327.0) が及んでいる。
* **内部テキスト (`Card Text`)**: 長文が入る前提のため、特定の幅(`Fixed`)で折り返される仕様。

## 🧩 子要素 (children)
1. [`Card Text`](./CardText.md) (別コンポーネントを参照)
