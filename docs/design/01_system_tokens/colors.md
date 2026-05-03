# 🎨 Color Tokens (momeo)

FigmaのVariables（バリアブル）で定義されているベースカラーの一覧です。
Flutterの `ColorScheme` 等を定義する際の基準になります。

| トークン名 | HEX (16進数) | 用途・状態の推測 |
| :--- | :--- | :--- |
| **Surface** | `#FFFFFF` | 背景やカードのベースカラー |
| **On Surface** | `#111827` | 背景の上に乗るメインテキスト・アイコン |
| **On Surface Variant** | `#6B7280` | サブテキスト・非アクティブな要素 |
| **Outline** | `#E5E7EB` | 境界線・ボーダー・区切り線 |
| **Primary** | `#EF4444` | プライマリカラー（メインのアクション・赤系） |
| **On Primary** | `#FFFFFF` | プライマリカラーの上に乗るテキスト |
| **Error** | `#EF4444` | エラー表示（Primaryを参照） |
| **Tertiary** | `#F4C542` | アクセントカラー（黄色系） |

> **Note:** 上記は `momery.tokens.json` をもとに自動生成されたベーストークンです。状況に応じてダークモード対応などを追加していきます。
