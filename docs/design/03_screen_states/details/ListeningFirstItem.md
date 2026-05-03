# Listening First Item

**UIプレビュー:**
![ListeningFirstItem](../../00_raw_assets/screenshots/ListeningFirstItem.png)

---

## 🎨 使用スタイル (01_system_tokens)
* **カード背景色**: `Surface` または設定された色
* **テキスト色**: `On Surface`

## 🧩 使用コンポーネント (02_components)
* **[`Voice Listening Card`](../../../02_components/details/VoiceListeningCard.md)**

## 📐 画面レベルのレイアウト仕様
* **画面全体の余白**:
  * 左右パディング: `28.0` (トークン外の固有値)
  * 上下パディング: 上 `68.0`, 下 `32.0` (`spacing-xxl`)
* **アイテム間余白 (ListView Gap)**:
  * カード間のGap: `spacing-xl` (24.0)

## 📝 状態特有の事実
* 最初のフレーズが音声認識され、リストに1つ目の要素として追加された瞬間のUI状態。
