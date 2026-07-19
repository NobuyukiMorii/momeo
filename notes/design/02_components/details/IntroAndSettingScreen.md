# Intro and Setting Screen

## 概要
権限系のベースになる大枠スクリーン。

## 🎨 構造と事実データ
* **適用レイアウトトークン**:
  * 左右のpadding: `spacing-xl`
  * 上下のpadding: トークン外の拡張余白 (safearea等による構成)

## 📏 伸縮ルール (Sizing & Constraints)
* **画面枠全体**: Width/Height ともに端末・親レイアウトに応じた固定 (`Fixed`) 相当。
* **内部のメイン要素 (`safearea` 枠 等)**: 横幅に対しては親の幅いっぱいに広がる (`Fill Container` /事実情報 `layoutAlign: STRETCH`)

## 🧩 子要素 (children)の詳細
* **`safearea`**
  * このレイヤーが巨大なGap（581px等の可変余白、FlutterではSpacerで実装予定）を持ち、上下の要素を引き離す役割を果たしている。
