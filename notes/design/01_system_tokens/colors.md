# 🎨 Color Tokens (momeo)

色は 2 段に分かれる。

| 段 | ファイル | 持つもの |
| :--- | :--- | :--- |
| パレット | `lib/foundation/app_palette.dart` | 生の色そのもの。`Color` リテラルを持つのはここだけ |
| 用途トークン | `lib/foundation/app_colors.dart` | 用途ごとの名前。値はパレットへの参照 |

1 つの色が複数の用途を兼ねるため（`#111827` は本文の文字色でもあり、塗りボタンの色でもある）、
値と用途を分けている。同じ値である理由が参照として残り、片方だけ変えてしまう事故も防げる。

---

## パレット

Tailwind のパレットに由来する値。

| 名前 | HEX |
| :--- | :--- |
| `white` | `#FFFFFF` |
| `gray200` | `#E5E7EB` |
| `gray500` | `#6B7280` |
| `gray900` | `#111827` |
| `red500` | `#EF4444` |
| `green600` | `#16A34A` |
| `blue600` | `#2563EB` |

---

## 用途トークン

| トークン名 | パレット | 用途 |
| :--- | :--- | :--- |
| `surface` | `white` | 画面やカードの背景 |
| `onSurface` | `gray900` | 背景の上の文字・アイコン・輪郭線 |
| `onSurfaceVariant` | `gray500` | 背景の上の、控えめな文字 |
| `outline` | `gray200` | 主張させたくない区切り線 |
| `primary` | `gray900` | 塗りボタン、選択中の強調 |
| `onPrimary` | `white` | `primary` の上に乗る文字 |
| `error` | `red500` | 取り消せない操作（削除など） |
| `onError` | `white` | `error` の上に乗る文字 |
| `caution` | `red500` | 注意を向けてほしい状態 |
| `safe` | `green600` | そのままでよい状態 |
| `link` | `blue600` | 文字の中の、押せる場所 |

### primary と onSurface の使い分け

どちらも `gray900` で、見た目は同じ色になる。次の基準で選ぶ。

- **塗り・選択中の強調** → `primary`（塗りボタン、選択中カードの塗りと枠）
- **それ以外の前景** → `onSurface`（文字、アイコン、カードの輪郭線、シートのつまみ、背景の波形）

---

## 参照のしかた

- **自前のウィジェット** → `AppColors` を直接参照する
- **Flutter 標準のウィジェット**（`FilledButton`, `AlertDialog` など）→ `AppColors.colorScheme` 経由で色が渡る

`AppTheme.light()` は `colorScheme` を渡すだけで、ボタンの色を個別に指定しない。
`primary` が `gray900` なので、標準ウィジェットはそのままアプリの見た目に揃う。

---

## Figma の Variables との対応

Figma 側は Material のロール名をそのまま並べた構成で、コード側とは次の点がずれている。

| 項目 | Figma | コード |
| :--- | :--- | :--- |
| `primary` | `#EF4444` | `#111827` |
| `error` | `{color.primary}` のエイリアス | `red500` を直接参照 |
| `tertiary` | `#F4C542` | 持たない |
| `caution` / `safe` / `link` | 持たない | `red500` / `green600` / `blue600` |

コード側では、アプリの主役である黒を `primary` に据えている。Figma を追随させる場合は
`primary` を `#111827` にし、`#EF4444` は `error` のみが持つようにする。

`momery.tokens.json` は Figma からの書き出しなので手で編集しない。
