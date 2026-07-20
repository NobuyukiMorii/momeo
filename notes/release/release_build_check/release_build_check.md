# リリースビルドの実機確認

store_release_plan.md の Phase 1 にある
「リリースビルドの実機確認」で何をするかをまとめる。

一言でいうと: **普段の `make run`（debug）ではなく release ビルドを実機に入れて一通り動かす**。

## なぜやるか（debug と release で変わる点）

| 違い | 影響 |
|---|---|
| Android のモデル読み込み経路 | 開発は手置き（内部ストレージ）、本番は fast-follow アセットパック。**本番経路は普段の開発で一度も通っていない** |
| Android release は R8 が有効 | Kotlin 側（AssetPackDeliveryChannel など）がクラス削除で壊れる可能性は release でしか分からない |
| Dart が AOT コンパイル | assert 無効化・実行速度が変わる。STT のレイテンシ・メモリは release が本番の姿 |

※ `Makefile` に `--obfuscate` は付けていないため、Dart 側の難読化は無効。
心配すべき「難読化」は実質 Android の R8 のみ。

※ iOS は `make run` も `make build-ios` も同じ配置スクリプト → バンドル同梱なので、
モデル経路の差はほぼない。

## やること

### iOS（軽い）

```bash
make models && bash scripts/place_ios_models.sh
flutter run --release -d <iOS実機のID>
```

release モードで起動して下のチェックリストを流すだけ。
ipa としての最終確認は Phase 2 の TestFlight 内部テストで兼ねる。

### Android（本命）

前提: **release ビルドでは開発用の手置きモデルが使えない**。

- インストール時に debug 版が消え、手置きモデル（アプリ内部ストレージ）も一緒に消える
- release アプリは debuggable でないため、`run-as` を使う手置きスクリプトで再配置もできない
- よって `flutter run --release` では STT まで確認できず、
「Try restarting」画面（モデル無しでエンジン起動に5回失敗した表示）で止まる。これは想定内

確認は bundletool の local-testing で行う。本番と同じ AAB を、
アセットパック（NeMo モデル）の配信ごと端末にインストールできる。

```bash
make build-android
bundletool build-apks \
  --bundle=build/app/outputs/bundle/release/app-release.aab \
  --output=/tmp/momeo.apks --local-testing
bundletool install-apks --apks=/tmp/momeo.apks
```

- 既に momeo が入っている端末では署名不一致で失敗することがある。
その場合は先に `adb uninstall jp.momeo` する（bundletool は既定で debug 署名を使うため）
- `--local-testing` は Play を経由せず、アセットパック配信を端末上でシミュレートする
- Play 実配信での最終確認は Phase 3 の内部テストトラックで行う

実行時の注意（実際に確認したときのメモ）:

- 1台の端末が USB と無線デバッグの両方で adb に見えていると「複数台」扱いになり
`install-apks` が失敗する。`--device-id=<adbシリアル>` で USB 側を指定する（転送が速い）
- `sun.misc.Unsafe` 系の WARNING と「signed with the debug keystore」の INFO は無視してよい
- インストール末尾の `run-as: package not debuggable` エラーは、旧バージョンの掃除に
失敗しただけで実害なし（release は run-as が通らないため）。インストール自体は成功している

## チェックリスト（両OS共通）

- [ ] 初回起動: 準備ゲートを通ってモデルが正しく検出される
（Android は DL 待ちの進捗表示・失敗時の再試行も）
- [ ] マイク許可 → 発話 → 文字化が動く（sherpa-onnx のネイティブライブラリが読めている）
- [ ] 認識のレイテンシ・精度の体感が debug と同等以上
- [ ] 長押しコピーなど主要操作を一通り
- [ ] アプリを kill → 再起動して、2回目以降の起動（モデル再検出）が正常
- [ ] クラッシュ時は `adb logcat` / Xcode コンソールで R8・ネイティブ起因かを確認
