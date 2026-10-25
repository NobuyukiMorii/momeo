# Step 6 Dart から、認識モデルの置き場所とダウンロードの扱いを消す

## 目的

step 4 で使われなくなった、SenseVoice の置き場所を探す処理と、Android のダウンロード（Play の自動ダウンロード）の進み具合を見る処理を、Dart から消す。

画面と文字化の動きは変えない。


| 項目 | 今 | この step の後 |
| --- | --- | --- |
| `SttModelProvisioner` | SenseVoice（本体・tokens）と Silero の3ファイルの置き場所を返す | Silero を端末へコピーして、その置き場所を返すだけ |
| Android のダウンロードの進み具合 | `sttModelDownloadStateProvider` が見ている | 見ない |
| 準備ゲート画面 | ダウンロードの % を出すフェーズがある（step 4 の後は使われていない） | そのフェーズが無い |
| 開発用カタログ | 「STT → モデル配置」で3ファイルの状態を見られる | 項目ごと無い |


ネイティブ側の窓口（iOS の `SttModelChannel`、Android の `AssetPackDeliveryChannel`）は、呼ばれなくなるだけで残る。消すのは step 7・8。

## やること

### 消すファイル

| ファイル | 中身 |
| --- | --- |
| `lib/platform/asset_pack_delivery.dart` | Android のダウンロードの窓口と、その状態（`AssetPackPhase`・`AssetPackState`） |
| `lib/pages/dev/catalog/sections/stt/stt_models_section.dart` | 開発用カタログの「モデル配置」 |
| `lib/widgets/downloading_progress_text.dart` | ダウンロードの % の表示。準備ゲート画面のほかには、カタログの見本でしか使っていない |


### 直すファイル

- `lib/stt/stt_model_provisioner.dart`
  - 残す: `ensureSilero` と、Silero の定数（`_kSileroAssetPath`・`_kSileroFileName`・`_kSileroExpectedBytes`）
  - 消す: SenseVoice の定数（本体・tokens・iOS の窓口・Android の置き場所とパック名）、`SttModelFile`・`SttModels`・`provision`、`modelDownloadState`・`watchModelDownload`・`requestModelDownload`、`_resolveModelPaths` から下の置き場所を探す処理、`_ModelPaths`
  - ファイル冒頭のコメントを、Silero だけの説明に直す
  - Silero のサイズの確かめ（`_measure`）を残すかは、`ensureSilero` が使っているかで決める
- `lib/providers/stt_providers.dart`
  - `sttModelDownloadStateProvider` を消す
  - import から `asset_pack_delivery.dart` と、使わなくなった `stt_model_provisioner.dart` を外す
- `lib/pages/preparation_gate_page.dart`
  - ダウンロードの % のフェーズ（`PreparationPhase.downloading`）と、`downloadState` を見る部分を消す
  - `_resolvePhase` は、エンジンの状態だけで決める
- `lib/pages/dev/catalog/catalog_page.dart`
  - 「モデル配置」の項目を消す
- `lib/pages/dev/catalog/sections/widgets/widgets_content_slide_switcher_section.dart`
  - 見本の `DownloadingProgressText` を、ほかの文言に差し替える
- `lib/pages/dev/catalog/sections/stt/stt_transcription_section.dart`
  - `provision()` を使っていれば、`ensureSilero()` に替える
- `lib/pages/dev/catalog/sections/stt/stt_engine_section.dart`
  - 冒頭のコメントの「Android のDL進捗・再試行は『STT → モデル配置』セクションが担当」を消す

※ 準備ゲート画面のフェーズは、この step の後は「読み込み中」「言語のモデルをダウンロード中」「再試行中」「アプリを再起動してください」「この端末では使えません」の5つになる。

## 確かめること

- `flutter analyze` が通ること
- iOS と Android で、今と同じく準備ゲート画面を抜けてリスニングに進み、文字にできること
- 開発用カタログの「VAD 区切り」「文字化」「エンジン常駐」が今と同じく動くこと
