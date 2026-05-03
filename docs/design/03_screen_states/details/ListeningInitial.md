# Listening Initial

**UIプレビュー:**
![ListeningInitial](../../00_raw_assets/screenshots/ListeningInitial.png)

---

## 🎨 使用スタイル (01_system_tokens)
* **背景**: 設定されたベースカラー
* **テキスト**: `On Surface` 

## 🧩 使用コンポーネント (02_components)
* **[`Icons`](../../../02_components/details/Icons.md)** (波形アイコン)

## 📐 画面レベルのレイアウト仕様
* **画面全体の余白**:
  * 左右パディング: `28.0` (トークンに属さない固有値)
  * 上下パディング: 上 `68.0`, 下 `32.0` (`spacing-xxl`)
* **アイテム間余白 (ListView Gap)**:
  * 要素が複数並ぶ際の間隔: `spacing-xl` (24.0)

## 📝 状態特有の事実
* アプリが音声認識を開始し、ユーザーの最初の発話（オーディオ入力）を待ち受けている初期状態。
