# fast-follow を Flutter からどう動かすか — 実装手段の調査

## この文書について

- **目的**: 「Android の NeMo を **fast-follow** で配る」と決めた後の宿題、**「Flutter から fast-follow をどう駆動するか（既製パッケージで足りるか／自前ネイティブが要るか）」** を調べて結論を出す。
- **対象読者**: この実装手段がまだ判断できていない開発者（＝この文書を依頼した本人）。
- **作成日**: 2026-06-24
- **前提**: 配信モードは fast-follow に決定済み（[model_delivery_decision_for_beginners.md](model_delivery_decision_for_beginners.md)）。本書はその「実装手段」だけを詰める。
- **結論（先に）**: **薄い自前ネイティブブリッジ（`AssetPackManager` を直接叩く）で駆動する**のが堅実。既製の `asset_delivery` パッケージは **on-demand 専用で fast-follow を面倒見ない**ため、コア機能の土台としては頼りにくい。**fast-follow の決定はそのまま有効**（実装手段が「パッケージ」から「薄い自前ブリッジ」に決まっただけ）。

---

## 0. 3行まとめ

- サイズの心配は無用。**公式の上限は1パック1.5GB**なので、NeMo（625MB）は**1つの fast-follow パックに余裕で収まる**（「512MB上限」は古い情報）。
- `asset_delivery` パッケージは **on-demand 専用**。fast-follow・`getPackLocation`・状態リスナーをラップしていないので、**fast-follow には使えない（少なくとも保証されない）**。
- なので fast-follow は **`AssetPackManager` を叩く薄い自前ネイティブブリッジ**で動かす。これは on-demand でも同じコードで動くので、将来モードを変えても流用できる。

---

## 1. そもそも何を決めたいのか

fast-follow は「Play がインストール直後に自動でモデルをDLし、`getPackLocation` で実パスを取る」仕組み（[model_distribution.md](../../on_device_stt/model_distribution.md)）。
これを **Flutter（Dart）側から扱う**には、Android ネイティブの API を呼ぶ必要がある。手段は2系統：

- **(A) 既製パッケージ `asset_delivery` に任せる** … 自前ネイティブを書かなくて済む（はず）。
- **(B) 自前で薄いネイティブブリッジを書く** … `AssetPackManager` を直接呼び、状態とパスを Dart に渡す。

どちらが妥当かを見極めるのが本書の目的。

---

## 2. 調べて分かったこと

### 2-1. サイズ上限：625MB は1パックに収まる（「512MB」は誤情報）

最初に「fast-follow は1パック512MBまで」という記事があり、625MB が入らない懸念が出た。
だが **Google Play の公式サイズ上限**を確認したところ：

| 項目 | 上限 |
|---|---|
| **個々のアセットパック** | **1.5GB** |
| install-time パック＋全モジュールの合計 | 4GB |
| on-demand／fast-follow パックの合計 | 30GB |

→ **NeMo（625MB）は1つの fast-follow パックに余裕で収まる**。「512MB」は古い／ゲーム枠などの別情報とみられ、現行の公式上限ではない。
（なお公式は「install-time はパック容量の**2倍**のディスクが要る」とも明記。これは以前指摘した install-time の「約1.25GB（同梱＋コピー）」を裏づける。）

### 2-2. `asset_delivery` パッケージは on-demand 専用

[`asset_delivery`](https://pub.dev/packages/asset_delivery)（GitHub: [mohsen-motlagh/asset_delivery](https://github.com/mohsen-motlagh/asset_delivery)）を精査した結果：

- README・API とも **on-demand しか想定していない**。install-time / fast-follow への言及なし。
- 公開 API は `fetch()`（DL起動）・`getAssetPackPath()`（DL後のパス）・`getAssetPackStatus()`（"COMPLETED" を見る簡易進捗）。
- **`getPackLocation` / `getPackStates` / `AssetPackStateUpdateListener` といった fast-follow 向けの細かい制御は公開していない**。
- 中身は Google の `AssetPackManager` を使っている（Gradle に `com.google.android.play:asset-delivery:2.2.2` を要求）。

> 結論：**fast-follow の「自動DL状態の監視」をこのパッケージで安全に行える保証がない**。`fetch()` 起点（on-demand）の作りなので、fast-follow のコア機能（アプリ未起動でも進む自動DL）とはズレる。

### 2-3. fast-follow に必要な Android API（自前なら何を呼ぶか）

fast-follow を正しく扱うのに必要なのは、`AssetPackManager` の以下くらい（いずれも公式）：

- `getPackStates()` / `registerListener(AssetPackStateUpdateListener)` … **DL状態・進捗・失敗**を取る。
- `getPackLocation(packName).assetsPath()` … 完了後の**実パス**を取る。
- （必要なら）`fetch()` … 明示的に取得を促す。fast-follow は自動DLなので必須ではないが、未DL時の保険に使える。

呼ぶ API はこれだけ。**薄いブリッジで十分**まかなえる。

---

## 3. Flutter からの実装手段：3案の比較

| 観点 | (A) fast-follow ×`asset_delivery` | (B) fast-follow ×自前ブリッジ（推奨） | (参考) on-demand ×`asset_delivery` |
|---|---|---|---|
| パッケージ対応 | ✗ 非対応（動くかは未保証） | —（自前） | ◯ 直接対応 |
| 自前ネイティブ | 不要だが**動作未保証** | 必要（Kotlin＋Dartで小規模） | ほぼ不要 |
| DL開始タイミング | アプリ未起動でも自動 | アプリ未起動でも自動 | アプリ起動して `fetch()` 後 |
| 状態・進捗の取得 | `getAssetPackStatus`（fast-followで効くか未検証） | `getPackStates`/listener で**確実** | `getAssetPackStatus`（対応） |
| 制御性・堅牢性 | 低（未対応に依存） | **高** | 中（パッケージ依存） |
| 第三者依存 | あり（v1.0.0・小規模メンテ） | なし | あり（同上） |

---

## 4. 推奨：薄い自前ネイティブブリッジ（B）

**コア機能（モデルが届かないとアプリが成立しない）なので、未対応パッケージの当て推量に乗らない。** 理由：

- `asset_delivery` は fast-follow を**そもそも想定していない**。動いても“たまたま”で、壊れたとき直せない。
- 必要な Android API はごく少数（§2-3）。**薄いブリッジで確実に・自分の制御下に**置ける。
- このブリッジは **on-demand でも同じ API（fetch/getPackStates/getPackLocation）** で動く。将来モードを変えても**コードを流用**できる。

> 別解：「Kotlin を一切書きたくない」場合は **on-demand に切り替えて `asset_delivery` を使う**選択肢もある。momeo はインストール後すぐオンボーディングで開くので、起動時に `fetch()` すれば「オンボーディング中にDL」という体験は fast-follow とほぼ同じにできる。ただしパッケージ（v1.0.0・小規模）への依存をコア経路に持ち込むことになる。
> → **本命は (B)**。どうしてもネイティブを避けたい時の保険が on-demand×パッケージ、という位置づけ。

---

## 5. 実装イメージ（薄いブリッジの骨格）

Dart 側は「モデルが使えるパスを返す」一点に絞る（**パス契約**）。Android 実装だけがブリッジを使い、iOS は同梱物を返す。

```text
[Dart] SttModelProvisioner
  Future<ModelPaths> ensureReady()   // 揃うまで待ち、実パスを返す
  Stream<DownloadProgress> progress  // 進捗（Androidのみ意味を持つ）

  ├─[Android impl] MethodChannel / EventChannel
  │    → registerListener / getPackStates  … 状態・進捗
  │    → getPackLocation(pack).assetsPath() … 実パス
  │    → （未DLなら）fetch(pack)
  │
  └─[iOS impl] 同梱物の実パスを返す（DL も状態も無い＝常に ready）
```

- Gradle（`android/app/build.gradle.kts`）に `com.google.android.play:asset-delivery:2.2.2` を追加。
- アセットパック用の小モジュール（`delivery = fast-follow`）を `settings.gradle.kts` に追加（現状 `:app` のみ）。
- 開発時は [step06_provision_models.md](../../on_device_stt/step06_provision_models.md) のとおり `adb push` 事前配置で回し、fast-follow 経路の確認だけ Step 8（[step08_android_fast_follow.md](../../on_device_stt/step08_android_fast_follow.md)）で `bundletool` を使って行う。

---

## 6. iOS はこの話と無関係

fast-follow も `AssetPackManager` も **Android だけ**の仕組み。iOS は NeMo を普通に同梱して実パスを渡すだけで、**DLも「未準備」状態も無い**。
よって §5 のとおり、ブリッジは Android 実装にだけ要り、iOS 実装は「常に ready」を返す。

---

## 7. この調査が前の決定に与える影響

- **fast-follow の採用はそのまま有効。** 変わったのは「実装手段＝`asset_delivery` ではなく薄い自前ネイティブブリッジ」と確定したことだけ。
- サイズ懸念（512MB）は**誤りと判明**したので、fast-follow を見直す必要はない。
- これにより「fast-follow を Flutter からどう駆動するか」は**結論済み**として [step08_android_fast_follow.md](../../on_device_stt/step08_android_fast_follow.md) 本文に反映済み（薄い自前ブリッジで確定）。

---

## 8. 関連ドキュメント / 出典

**関連ドキュメント**
- [model_delivery_decision_for_beginners.md](model_delivery_decision_for_beginners.md) — fast-follow 採用の判断（本書はその実装手段編）
- [model_distribution.md](../../on_device_stt/model_distribution.md) — 配布方式の詳細
- [step08_android_fast_follow.md](../../on_device_stt/step08_android_fast_follow.md) — Android fast-follow 本配信の実装計画（本書の結論の反映先）
- [step06_provision_models.md](../../on_device_stt/step06_provision_models.md) — 配置とパス契約の土台

**出典**
- [Play Asset Delivery — Android Developers](https://developer.android.com/guide/playcore/asset-delivery)
- [Google Play のサイズ上限（answer 9859372）](https://support.google.com/googleplay/android-developer/answer/9859372)
- [AssetPackManager — API reference](https://developer.android.com/reference/com/google/android/play/core/assetpacks/AssetPackManager)
- [AssetPackStateUpdateListener — API reference](https://developer.android.com/reference/com/google/android/play/core/assetpacks/AssetPackStateUpdateListener)
- [asset_delivery | pub.dev](https://pub.dev/packages/asset_delivery) ／ [GitHub: mohsen-motlagh/asset_delivery](https://github.com/mohsen-motlagh/asset_delivery)
