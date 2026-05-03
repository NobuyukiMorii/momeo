# Listening Third Item & Many Items

**UIプレビュー:**
![ListeningThirdItem](../../00_raw_assets/screenshots/ListeningThirdItem.png)
![ListeningManyItems](../../00_raw_assets/screenshots/ListeningManyItems.png)

---

## 🎨 使用スタイル (01_system_tokens)
* スクロール可能なエリアを含む全体のカラー・余白設定

## 🧩 使用コンポーネント (02_components)
* **[`Voice Listening Card`](../../../02_components/details/VoiceListeningCard.md)**
* **[`Voice Card`](../../../02_components/details/VoiceCard.md)**
* **[`Voice Card With DateTime`](../../../02_components/details/VoiceCardWithDateTime.md)**

## � 画面レベルのレイアウト仕様
* **画面全体の余白**:
  * 左右パディング: `28.0` (トークン外の固有値、セーフエリア扱い)
  * 上下パディング: 上 `68.0`, 下 `32.0` (`spacing-xxl`)
* **アイテム間余白 (ListView Gap)**:
  * 無数に並ぶカードたちの間隔: `spacing-xl` (24.0)

## �📝 状態特有の事実
* 要素が増えてスクロールが発生する状態。古いアイテムには日時のついたカードが使用される等。
