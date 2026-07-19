# Voice Listening Card

## 概要
音声認識中の状態を示すカードコンポーネント。

## 🎨 構造と事実データ
* **適用レイアウトトークン**:
  * padding (四方すべて): `spacing-l`
  * 子要素間Gap: `spacing-l`
  * 角丸: `radius-l`
* **適用カラートークン**:
  * 背景色: `Surface`

## 📏 伸縮ルール (Sizing & Constraints)
* **カード全体**: 横幅・高さ共にコンテンツに合わせて伸縮 (`Hug`)
* **内部レイアウト**:
  * `Voice Icon`: 固定サイズ (`Fixed`)
  * `Card Text`: 残りの横幅をすべて埋める (`Fill Container` /事実情報 `layoutGrow: 1.0` = Flutterの `Expanded` 相当)

## 🧩 子要素 (children)
1. [`Voice Icon`](./Icons.md)
2. [`Card Text`](./CardText.md)
