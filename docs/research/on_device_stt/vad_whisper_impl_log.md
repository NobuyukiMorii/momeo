# VAD + Whisper 実装記録（観察セクション・クラッシュ究明・性能調査）

## この文書について

- **目的**: `recording_segmentation_whisper.md` で具体化した「連続録音 → 無音区切り(VAD) → Whisper バッチ転写 → 保存」パイプラインを、**実機で観察するための dev セクションとして実装した経緯**と、その過程で起きた**クラッシュの原因究明**・**転写が遅い問題の性能調査**を時系列で残す。
- **作業日**: 2026-06-13
- **対象端末**: Pixel 8a（Tensor G3 / Android 16）。デバッグビルドで `flutter run`。
- **前提**: momeo は「日本語が主」「常時リスニングでメモ化」「プライバシー重視（オンデバイス）」「個人開発」。
- **関連文書**:
  - `recording_segmentation_whisper.md`（パイプラインの部品調査・本命設計）
  - `next_stt_approaches.md`（方向づけ）
  - `continuous_listening_limitation.md`（現方式がダメな理由）

---

## TL;DR（結論サマリ）

- **採用スタックは `vad`（Silero VAD）＋ `whisper_flutter_new`（whisper.cpp）に確定**。第一候補だった `whisper_ggml` は **riverpod 2.x 依存**が本プロジェクトの riverpod 3 と衝突して導入不可だった。
- **dev カタログ Packages に観察セクション**を新規追加（`packages_vad_whisper_section.dart`）。本番 `ListeningPage` への結線は、精度・速度を実機で確かめてから行う方針。
- **致命的バグ①: 起動時の SIGSEGV クラッシュ** → 原因は「**Whisper モデルのダウンロードが途中で切れ、4.4MB の壊れたファイルが保存されていた**」。同梱の `downloadModel` が HTTP ステータスも Content-Length も検証しないのが根因。**検証付きの自前ダウンローダ**（`whisper_model_downloader.dart`）で解決。
- **問題②: 転写が遅い（2.4秒の音声に17秒）** → ネイティブ実装が**発話ごとに 465MB のモデルを毎回フルロード→推論→解放**しており、しかも**CPU 専用の古い whisper.cpp ビルド**。これが遅さの構造的な原因。
- **高速化方針**: まず **A. 量子化 small（q5_1, 181MB）を観察セクションに足して実測比較**。本命は **B. モデル常駐（毎回ロード廃止）＋軽量/量子化モデル**。本方式は「発話終了後にバッチ転写」する設計のため、**原理的に数百ms〜数秒の遅延は必ず残る**（リアルタイム表示が欲しいなら別アーキテクチャ）。

---

## 1. 実装したもの

### 追加・変更したファイル

| ファイル | 役割 |
|---|---|
| `lib/pages/dev/catalog/sections/packages/packages_vad_whisper_section.dart` | **観察セクション本体**。VAD でマイクを掴み、発話終了で WAV 化 → Whisper でバッチ転写し、発話ごとに「セグメント」として結果を並べる。メソッド/状態/ライブ/セグメント/オプション/ログの6セクション構成（`speech_to_text` セクションと同じ流儀） |
| `lib/utils/wav_writer.dart` | VAD が返す `List<double>`（16kHz/モノラル/-1.0〜1.0）を **16bit PCM の WAV ファイル**に変換。whisper_flutter_new の入力が「WAVファイルパス」のため |
| `lib/utils/whisper_model_downloader.dart` | **整合性検証付き**のモデルダウンローダ（後述のクラッシュ対策で追加） |
| `lib/pages/dev/catalog/catalog_page.dart` | Packages セクションに「vad + whisper」項目を追加 |
| `android/app/src/main/AndroidManifest.xml` | `MODIFY_AUDIO_SETTINGS`（vad のマイク設定）・`INTERNET`（モデル初回DL）を追加 |
| `ios/Podfile`, `ios/Runner.xcodeproj/project.pbxproj` | iOS デプロイメントターゲットを **15.1** に引き上げ |
| `pubspec.yaml` | `vad ^0.0.8`, `whisper_flutter_new ^1.0.1` を追加 |

### パイプラインの流れ（観察セクション内）

```text
vad がマイクを掴みっぱなしで連続キャプチャ
  ↓ onSpeechStart / onRealSpeechStart（発話開始）
  ↓ onSpeechEnd（発話終了）→ List<double> サンプルが届く  ← 転写トリガー
WavWriter で 16bit PCM WAV に変換
  ↓
whisper_flutter_new.transcribe(WAVパス, language: ja)
  ↓
発話ごとに1件「セグメント」として転写結果を表示
```

- 転写は `_transcribeChain`（Future チェーン）で**1件ずつ直列化**。発話が連続してもセグメントが重ならないようにしている。
- **VAD の `onSpeechEnd` が「メモカード確定トリガー」**になる。これは `recording_segmentation_whisper.md` で意図したとおりで、旧 `speech_to_text` の `onStatus='done'` を置き換えるもの。

---

## 2. 採用スタックの決定と理由

| 段 | 採用 | 理由 / 経緯 |
|---|---|---|
| VAD | **`vad`（Silero VAD）** | マイク所有・PCM 連続キャプチャ・発話区切りを1パッケージで提供。`onSpeechEnd` でサンプルが直接届く。VAD モデルは初回に CDN（jsDelivr）から取得（`silero_vad_legacy.onnx` 約1.8MB） |
| Whisper | **`whisper_flutter_new`** | 第一候補の **`whisper_ggml` は flutter_riverpod ^2.x に依存**し、本プロジェクトの **riverpod 3.3.1 と version solving が衝突**して導入不可。同じ whisper.cpp 系で **riverpod 非依存・モデルパス指定可**の `whisper_flutter_new` に切り替えた |

### 付随する制約（ハマりどころ）

- **iOS 15.1 以上が必須**: `vad` が依存する `onnxruntime-objc 1.22.0` が iOS 15.1 を要求。Podfile と project.pbxproj を 13.0 → 15.1 に変更済み。
- **モデルは初回にネットからDL**: VAD モデル（CDN）と Whisper モデル（HuggingFace）。`INTERNET` 権限が必要。アプリにバンドルはしていない。
- **モデルの保存先**: `getApplicationSupportDirectory()/whisper_models/`（Android では `/data/user/0/jp.momeo.momeo/files/whisper_models/`）。**端末に1回DLすれば以降は再利用**（毎回DLではない）。

---

## 3. つまずきと解決（時系列）

### 3-1. `whisper_ggml` の riverpod 衝突（導入前）

`flutter pub add vad whisper_ggml` が version solving で失敗。`whisper_ggml` → `flutter_riverpod ^2.3.10`、本プロジェクト → `^3.3.1`。**riverpod の依存が外れない限り `whisper_ggml` は採用不可**。→ `whisper_flutter_new` に切り替えて解決。

### 3-2. iOS デプロイメントターゲット不一致

`vad` の podspec が `:ios, '15.1'` を要求。プロジェクトは 13.0 だった。→ Podfile（`platform :ios, '15.1'` と post_install での `IPHONEOS_DEPLOYMENT_TARGET = '15.1'`）、pbxproj の3箇所を 15.1 に修正。

### 3-3. 起動時の「16 KB アライメント」警告（Android 16）

実機起動時に「Android アプリの互換性」ダイアログが出て、`libwhisper.so` / `libonnxruntime.so` 等が **16KB ページにアライメントされていない**と警告。

- **結論: 開発・デバッグでは問題なし**（警告であってクラッシュではない。アプリは起動して動く）。
- 16KB ページサイズは Android の移行要件。`libwhisper.so`（whisper_flutter_new）・`libonnxruntime.so`（vad）等の**プリビルド .so のアライメント**の話で、こちらの Dart コードのバグではない。
- **影響するのは将来 Google Play へ公開する時**（Android 15+ ターゲット、2025/11〜の Play 要件）。その時に各パッケージが 16KB 対応の .so を出す必要がある。観察段階の今は無視してよい。

### 3-4. 致命的: 起動して話すと SIGSEGV クラッシュ（最重要）

**症状**: リスニング開始 → 1回話すと `libwhisper.so` 内で `Fatal signal 11 (SIGSEGV) ... fault addr 0x180`（null ポインタ参照）。アプリが落ちる。Dart の try/catch では捕まらない（ネイティブクラッシュのため）。

**究明の手順（推測で直さず、ログで切り分け）**:

1. ネイティブクラッシュなので Dart 例外として捕捉できない。→ **転写に渡す直前の入力（WAVサイズ・サンプル数・モデルファイルの実サイズ・パス）を記録する診断ログ**を仕込んだ。あわせて `_log` が `debugPrint` でコンソール（logcat）にも出るようにした。
2. **`adb shell run-as jp.momeo.momeo ls -la files/whisper_models/`** で端末上のモデルを直接確認 → **`ggml-small.bin` が 4,616,436 バイト（約 4.4 MB）**しかなかった。

**根因**: `ggml-small.bin` の正しいサイズは **487,601,967 バイト（約 465 MB）**。つまり**ダウンロードが途中で切れた壊れたファイル**だった。これを whisper.cpp が読む → `whisper_init_from_file` が NULL を返す → その NULL コンテキストを使って処理続行 → null ポインタ参照でクラッシュ、という流れ。

なぜ途中で切れるか: 同梱の `downloadModel` は

```dart
final response = await request.close();
final raf = file.openSync(mode: FileMode.write);
await for (var chunk in response) { raf.writeFromSync(chunk); }
await raf.close();   // ← ステータスもサイズも検証せず「成功」扱い
```

と、**HTTP ステータスも Content-Length も検証していない**。HuggingFace は `resolve/main/...` から **302 で Xet CDN（cas-bridge.xethub.hf.co）へリダイレクト**する方式で、回線が不安定だと途中で切れやすい。切れても壊れたファイルが「成功」として残る。

**解決**: `lib/utils/whisper_model_downloader.dart` を新規作成し、次の保証を付けた。

- HTTP 200 以外は失敗として扱う
- **サーバ申告サイズ（Content-Length）と実書き込みサイズの一致を検証**
- `.download` 一時ファイルに書いてから**本ファイル名へ原子的にリネーム**（途中で切れたら本ファイルは作られない＝壊れたモデルを二度と使わせない）
- 既存ファイルも**最小サイズの下限**でざっくり健全性チェックし、壊れていれば自動で再取得

観察セクションの `_prepareModel` をこのダウンローダに差し替え、**10%刻みのDL進捗ログ**も追加。壊れた 4.4MB は `adb` で削除し、再DLで **465.0 MB** を確認してクラッシュ解消。

---

## 4. 性能調査: 転写が遅い問題（2.4秒の音声に17秒）

クラッシュ解消後、転写は動いたが **seg#1（2.4秒・38400サンプル）の転写に 17,153ms（約17秒）**かかった。原因をネイティブ実装まで掘った。

### 4-1. ネイティブ実装の解析（`whisper_flutter_new/src/main.cpp`）

```cpp
json transcribe(json jsonBody) {
  ...
  struct whisper_context *ctx = whisper_init_from_file(params.model.c_str()); // ← 毎回ロード
  ...
  whisper_full(ctx, wparams, pcmf32.data(), pcmf32.size());                   // 推論
  ...
  whisper_free(ctx);                                                          // ← 毎回解放
}
```

**発話セグメントごとに 465MB のモデルをディスクから丸ごとロード → 推論 → 解放**している。`request()` は一発勝負のステートレス API で、**モデルを常駐させる仕組みがない**。連続録音で短い発話を何度も転写する今回の用途には最悪の作り。

### 4-2. バンドルされている whisper.cpp が古く CPU 専用

- `src/whisper.cpp/` は**単一 `ggml.c` 時代の古い版**（`ggml-backend` / `ggml-metal` / `ggml-cuda` 等の**GPUバックエンドのソースが一切ない**）。**CPU 専用**で、近年の高速化が入っていない。
- ビルドフラグは `-O3 -flto=thin`、arm64 で `-march=armv8.2-a+fp16`。NEON/fp16 は効くが、それ以上の加速はなし。
- **量子化（Q5_1, Q8_0 など）は ggml.h で完全対応**。→ 量子化モデルはこのパッケージのままロード可能。

### 4-3. 遅さの原因分解

| 要因 | 内容 | 効き目 |
|---|---|---|
| ① 毎回フルロード | 発話ごとに 465MB をロード→解放 | 大 |
| ② small(fp16) × CPU専用の古いビルド | GPU/NNAPI 不使用。small は元々重い | 大 |
| ③ 初回コールドスタート | seg#1 は 465MB がディスクキャッシュ未load。**17秒は初回ゆえの誇張値**で、2回目以降は速くなる（今回 seg#2 完了前に停止したため未計測） | 中 |
| ④ threads=6 | Pixel 8a の省電力コアまで使い最適でない可能性（ネイティブ既定は `min(4, hw)`） | 小 |

### 4-4. 量子化モデルの実体（HuggingFace `ggerganov/whisper.cpp`、実測）

| モデル | サイズ | 位置づけ |
|---|---|---|
| ggml-tiny.bin | 74 MB | 速いが日本語精度低 |
| ggml-base.bin | 141 MB | 中間 |
| **ggml-small.bin（現用・fp16）** | **465 MB** | 精度◎・重い |
| **ggml-small-q5_1.bin** | **181 MB** | 精度ほぼ small・軽い（**A の本命**） |
| ggml-small-q8_0.bin | 252 MB | 精度 small・やや軽い |
| ggml-base-q5_1.bin | 57 MB | 速い・精度は base 相当 |

### 4-5. 高速化手段（効果順）と現実的な見積もり

あくまで概算・要実測（1発話あたり・定常）:

| 構成 | 目安 | 備考 |
|---|---|---|
| 今: small fp16 + 毎回ロード | 約7秒（初回のみ17秒） | 重い |
| ①: small-q5_1 + 毎回ロード | 約3〜5秒 | ロード量↓＋推論↓ |
| ③: モデル常駐 + small-q5_1 | 約2〜4秒 | 毎回ロード分が消える |
| 常駐 + base-q5_1 | 約1〜2秒 | 精度は base 相当 |

**重要な原理**: 本方式は「**発話が終わってからバッチ転写**」するため、**話し終えてから数百ms〜数秒の遅延は必ず発生**する。リアルタイムに文字が出るわけではない（逐次表示が欲しいなら**ストリーミングSTT**という別アーキテクチャが必要）。

補足: `kotoba-whisper`（日本語特化 distil 系）は**精度**には効くが、大きい encoder を積むため**スマホCPUでの速度はむしろ不利な可能性**。速度目的なら ①/③/base 系が主役、kotoba は精度の別軸。

---

## 5. A（量子化 small）の実測結果と構造的な結論（2026-06-13）

`small-q5_1`（181MB）+ `threads=4` で実機計測（Pixel 8a）。

| seg | 音声長 | 転写時間 | 結果 |
|---|---|---|---|
| seg#1 | 0.9s | 577ms | （空・無音判定） |
| seg#2 | 6.1s | 12,303ms | こうやっていろいろお話をしていると… |
| seg#3 | 2.0s | 13,755ms | いろいろつぶやいって |
| seg#4 | 2.1s | 13,332ms | 話しかけています |
| seg#5 | 1.3s | 13,309ms | リスムーズに |
| seg#6 | 2.7s | 13,973ms | テンシャーできるでしょうか |
| seg#7 | 2.9s | 14,766ms | どういう結果になるのか楽しみです |

**定常で約12〜15秒。量子化（A）は期待ほど効かなかった**（4-5 の「q5_1 で約3〜5秒」という見積もりは外れ）。

**決定的な事実: 転写時間が音声長にほぼ依存せず一定**（1.3秒も6.1秒も約13秒）。遅さの主因は「モデルサイズ」でも「音声長」でもなく、**1回の転写ごとの固定コスト**。ソースで裏取りした構造的原因は2つ:

- **encoder が30秒固定枠で動く**: `WHISPER_CHUNK_SIZE=30`、`n_audio_ctx=1500`。短い音声も30秒にパディング（`whisper.cpp` の `samples_padded`）して encoder を回すため、発話が1秒でも30秒分の計算をする。
- **毎回モデルをロード/解放**（既知）。

→ 量子化は「重みのデータ量」を減らすだけで、**この固定 encoder 計算量にも毎回ロードにも効かない**。だから大きく改善しなかった。

### 軽量モデル（base-q5_1）の実測 — 「軽いモデルでの底」

同じ手順で `base-q5_1`（57MB）に切り替えて計測（threads=4）。

| seg | 音声長 | 転写時間 | 結果 |
|---|---|---|---|
| seg#8 | 4.1s | 3,634ms | このような感じで 話します。 |
| seg#9 | 3.1s | 3,685ms | ブツブツブツと話していますか |
| seg#10 | 2.0s | 4,730ms | 一切に早くなるのかどうか。 |
| seg#11 | 1.1s | 4,232ms | わかりません きゃあ |

**定常で約3.6〜4.7秒。small-q5_1（約13秒）の 1/3 程度に短縮**でき、体感は「ギリギリ実用」。ここでも**音声長にほぼ依存せず一定**で、固定コスト（encoder枠＋毎回ロード）が主因という結論を裏付ける（encoder が小さいぶん固定コスト自体が下がった）。

ただし **base は日本語精度が落ちる**（「一気に」→「一切に」、語尾の崩れ「わかりません きゃあ」など）。small より明確に誤認識が増える。

→ **「base まで落とせば速度は実用圏に入るが、精度が犠牲」**という現状のトレードオフが明確になった。**精度（small）を保ったまま同等の速度**を出すには、結局この後の「audio_ctx＋常駐」のネイティブ改修（B-1）が要る。

### まだ使っていない高速化レバーが2つある（ともにネイティブ改修が必要）

`whisper.cpp` 本体には対策があるが、**同梱 `main.cpp` が使っていない**（`threads` と `language` しか設定していない）。

1. **`audio_ctx`（encoder 枠の縮小）**: `whisper_full_params.audio_ctx`（`whisper.h` L378）で encoder の枠を 1500 より小さくできる（`whisper.cpp` L1463 `exp_n_audio_ctx > 0 ? ...` で反映）。VAD の発話は数秒なので **`audio_ctx` を ~256〜512（≒5〜10秒相当）に絞れば encoder 計算量が大幅減**。短い発話の固定コストに直接効く。**同梱 main.cpp は audio_ctx を渡していない**ため、フォークして JSON 経由で渡す改修が必要。
2. **モデル常駐**: 同梱 main.cpp は `whisper_init_from_file`→`whisper_free` を毎回実行。初回ロード後は使い回す形にすればロード分（~1〜3秒）が消える。

この2つ（＝ネイティブ層のフォーク）を入れれば、**small q5_1 のまま** 約13秒 → おそらく **3〜5秒、短い発話なら2〜3秒**まで下げられる見込み（要実測）。

### B-1 実装メモ（2026-06-13・実機検証待ち）

`whisper_flutter_new` を **リポジトリ内にフォーク**して上記2点を実装した。

- **取り込み**: `packages/whisper_flutter_new/`（pub-cache からコピー、`example/` と `.cxx` は削除）。`pubspec.yaml` の `dependency_overrides` で同名上書き。import は `package:whisper_flutter_new/...` のまま。
- **ネイティブ `src/main.cpp`**:
  1. `whisper_params` に `audio_ctx` を追加し、リクエストJSONの `audio_ctx`（あれば）を `wparams.audio_ctx` に渡す。
  2. `whisper_context` を `static` で常駐させる `get_or_init_context()` を追加。**同じモデルパスなら使い回し**、変わったら作り直す。末尾の `whisper_free` を削除。
  3. ついでに **モデルロード失敗時の NULL チェック**を追加（以前の SIGSEGV をネイティブ側でも防ぐ）。
- **Dart `lib/whisper_flutter_new.dart`**: `transcribe({..., int audioCtx})` を追加。`_request` で DTO の JSON に `audio_ctx` を差し込む（freezed 再生成を避けるため文字列を組み立て直す）。
- **観察セクション**: `audio_ctx`（既定1500/768/512/384/256）と `threads` を UI で切替可能に。初期値 `audio_ctx=512`。
- **常駐の確認方法**: Android では native の `fprintf(stderr)` は logcat に出ないため、**2発話目以降の転写時間**で判断（reuse ならロード分が消える）。
- **ビルド注意**: 反映されない時は `flutter clean` してから `flutter run`。

### B-1 実測結果（small-q5_1 / audio_ctx=512固定 / 常駐, 2026-06-13）

| seg | 音声長 | 転写時間 | 結果 |
|---|---|---|---|
| seg#1 | 1.8s | 4,000ms | こんにちは これで |
| seg#2 | 2.2s | 4,437ms | いろいろ 僕の話が |
| seg#3 | 1.2s | 4,009ms | 見えますかね |
| seg#4 | 1.7s | 4,342ms | いい感じかもしれません |
| seg#5 | 5.1s | 4,003ms | ちょっとピーロンを飲んでいますか?どれくらいのスピードになるでしょう? |

**small-q5_1 が約13秒 → 約4秒（約3倍速）に短縮。** これで「**small の精度のまま base 並みの速度**」を達成（base-q5_1 ≒ 3.6〜4.7秒だが精度は低い）。精度/速度フロンティアは確実に前進した。今回の主役は **audio_ctx（30秒→10秒枠 ≒ 3倍）**で、常駐の寄与は小さめ（181MB は OS キャッシュに乗ると毎回ロードが ~0.5〜1秒と軽いため。fp16 465MB なら常駐がもっと効く）。

**ただし依然 約4秒で一定**（1.2秒の発話も4秒）。理由は audio_ctx=512 も「**固定10秒枠**」だから。枠が固定である限り、短い発話も枠ぶんの encoder 計算をする。

### 追加対策: audio_ctx を「自動（発話長連動）」に（2026-06-13）

固定枠だと短い発話が速くならないので、**発話長から必要な枠だけ算出する自動モード**を観察セクションに追加（`_resolveAudioCtx`）。`枠 ≒ 秒×50 ＋余白(15%+16)`、下限64(≒1.3秒)・上限1500。狙いは「短い発話ほど速く」。

### 自動 audio_ctx の実測（2026-06-13）— 逆効果だった

small-q5_1 / 自動 audio_ctx で計測。結果は **ばらつきが大きく、むしろ悪化**した。

| seg | 音声長 | audio_ctx(auto) | 転写時間 | 結果 |
|---|---|---|---|---|
| seg#1 | 2.9s | 182 | 7,319ms | （空） |
| seg#2 | 5.6s | 337 | 2,649ms | これがま どれぐらいの時間で 転車されるか…（良） |
| seg#3 | 1.6s | 110 | 3,213ms | 見たいどうなっていくんでしょか?（やや崩れ） |
| seg#4 | 1.4s | 99 | 7,455ms | うん、まだも。（崩れ） |
| seg#5 | 3.2s | 199 | 7,226ms | （空） |
| seg#6 | 5.5s | 331 | 2,566ms | これだとやっぱり足りない…（良） |

**観察と仮説:**
1. **audio_ctx を小さくし過ぎると逆に遅く・不正確**。枠 ~330 のときは良好＆速い（2.6秒）が、~100〜200 のときは空や崩れが出て 7秒台。仮説: 枠が小さいと encoder 出力が劣化 → 信頼度低下で whisper の **temperature fallback（最大6回の再デコード）**が走り、遅く＆悪くなる。**固定 512（前回 ~4秒・正確）の方が良かった**。
2. **新事実: VAD と whisper が CPU を奪い合う**。転写の速さが「話している最中(VAD稼働中)＝~7秒」「沈黙中＝~2.6秒」と強く相関（例: seg#1/#4/#5 は次の発話を喋っている最中の転写で7秒台、seg#2/#6 は沈黙中で2.6秒）。**連続発話＝本来の用途ではこの競合で各転写が遅くなり、バックログも積む**。

→ **自動 audio_ctx は撤回**（既定は固定 512 に戻し、-1=自動は実験用に残置）。UI の audio_ctx 行のはみ出しバグも修正（Expanded 化）。

### 結論（重要）— 速度改善は頭打ち、本質はバッチ方式の遅延

ここまでで「**速度の改善は頭打ち**」が見えた。small 精度を保つ限り、**1発話あたり ~3〜4秒、連続発話＋VAD競合下では ~7秒**が現実的な下限。そして根本問題として：

- **本方式は「発話終了後にバッチ転写」なので、どれだけ最適化しても“話し終えてから数秒の遅延”が原理的に残る**。逐次的に文字が出る体験にはならない。
- メモ用途として「数秒待てば確定テキストが出る」を許容できるなら現状でも成立するが、「話しながら出る」体験は得られない。
- さらに VAD↔whisper の CPU 競合で、連続して喋るほど遅延が伸びる。

→ **「リアルタイム／低遅延の体験」を求めるなら、保留中の B-2（`sherpa_onnx` の streaming transducer 等）＝ストリーミングASRへの路線変更が必要**。バッチ方式（VAD区切り→Whisper）はここが上限。

---

## 6. 今後の方針（更新）

- **A は単体では不十分**と実測で確定（構造的に encoder 30秒枠＋毎回ロードが主因）。
- **暫定の実用ライン**: `base-q5_1` なら定常 約3.6〜4.7秒で「ギリギリ実用」。精度が許せる用途の当座しのぎにはなる（ただし日本語精度は small より落ちる）。
- **採用: B-1 = ネイティブ層のフォーク**で「**`audio_ctx` の縮小**」＋「**モデル常駐**」を入れる。small の精度を保ったまま固定コストを削れる、最も筋の良い道。**これに着手する**。
- **保留: B-2 = 加速エンジンへ移行（`sherpa_onnx`）**。`sherpa_onnx` は onnxruntime の **NNAPI/XNNPACK 加速**が使え、さらに **streaming transducer（逐次表示・リアルタイム）** モデルも選べる（「話しながら出る」体験まで狙える）。ただし API・モデルが別物で**移行コスト大**、日本語ストリーミングモデルの入手と精度確認が必要。**B-1 が不十分だった場合の次の検証アイデアとして保留**する。
- **精度の別軸**: q5_1 small でも日本語に誤りあり（「転写」→「テンシャー」、「スムーズに」→「リスムーズに」等）。精度重視なら `kotoba-whisper`。ただし速度はスマホCPUで不利な可能性。
- **原理的限界**: 本方式は「発話終了後にバッチ転写」なので、どれだけ速くしても**話し終えてから数秒の遅延は残る**。完全な逐次表示が要るならストリーミングASRが必要。

### 残タスク（精度・速度の検証後）

- 本番 `ListeningPage._addMemo` への結線
- `listening_flow.md` を「VAD の onSpeechEnd を確定トリガーとする」前提に改訂
- kotoba-whisper の ggml 入手と互換・速度の検証（精度路線）
- リリース時: 16KB アライメント対応、モデルの軽量化（量子化）とオンボーディングでのDL UX、Wi-Fi限定DL・途中再開

---

## 7. B-2: sherpa-onnx（日本語）実装と実測（2026-06-13）

「話し終えて数秒」を解消するため B-2 に着手。まず候補を調査した結果、**日本語の streaming(online) zipformer は未提供**（sherpa の online モデルは zh/en/ko/bn のみ）と判明。日本語は **offline の ReazonSpeech zipformer transducer** が本命だった（[k2-fsa docs](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-transducer/zipformer-transducer-models.html)）。これは VAD区切り→デコードという点では今と同系統だが、エンジンが激速。

### 実装メモ
- パッケージ: `sherpa_onnx ^1.13.2`（riverpod 衝突なし）。新セクション `sherpa-onnx (ja)`（`packages_sherpa_onnx_ja_section.dart`）を Catalog > Packages に追加。
- API: `initBindings()` → `OfflineRecognizer(OfflineRecognizerConfig(transducer: encoder/decoder/joiner, tokens))` → `createStream()` → `acceptWaveform(Float32List, 16000)` → `decode()` → `getResult().text`。VAD の onSpeechEnd サンプルをそのまま渡す。
- モデル: `sherpa-onnx-zipformer-ja-reazonspeech-2024-08-01`（GitHub Releases の tar.bz2 約680MB のみ。個別HFなし）。int8 一式（encoder 147MB + decoder 11MB + joiner 2.7MB + tokens）を Mac で展開し、**adb の run-as でアプリ内部ストレージへ配置**（外部領域は adb 作成ファイルにアプリ uid がアクセス不可で Permission denied）。`flutter run` はクリーン再インストールで uid が変わり内部データが消えるため、配置後は **ホットリスタート(R)** で検証。
- ビルド: `vad` と `sherpa` が **`libonnxruntime.so` を二重同梱**するため、`android/app/build.gradle.kts` に `packaging { jniLibs { pickFirsts += "**/libonnxruntime.so" ... } }` を追加。実行時の VAD 初期化も問題なし。

### 実測結果 — 桁違いに速い

| seg | 音声長 | 転写時間 | 結果 |
|---|---|---|---|
| seg#1 | 3.3s | 142ms | どういうふうになるんでしょうか |
| seg#2 | 1.0s | 45ms | これは |
| seg#3 | 3.4s | 111ms | いろいろ話しているけれども |
| seg#4 | 2.5s | 89ms | 何かいろいろすぐに出てくるな |
| seg#5 | 1.8s | 69ms | けっこういいかもしれない |
| seg#6 | 1.2s | 52ms | 早いぞ |
| seg#7 | 0.8s | 43ms | いい |

**43〜142ms（RTF ~0.05）。whisper の ~4000ms に対し約30〜90倍速**。しかも**時間が音声長に比例**（whisper の固定枠と違い真の transducer）。短い発話は一瞬で、体験は「話し終えて即」。

### エンジン比較（まとめ）

| エンジン | 1発話の転写 | 日本語精度 | 体験 |
|---|---|---|---|
| whisper small-q5_1（B-1: audio_ctx512+常駐） | ~4秒（競合下~7秒） | 高 | 話し終えて数秒 |
| base-q5_1 | ~3.6〜4.7秒 | 低（崩れ多） | ギリギリ |
| **sherpa-onnx ja（ReazonSpeech int8）** | **43〜142ms** | 中〜やや高（句読点なし） | **話し終えて即（現状ベスト）** |

### 所見と精度改善の余地
- 内容自体は概ね正確（base のような崩れ無し）。「精度が少し足りない」と感じる主因は **句読点が付かない**こと＋ int8/greedy。
- 改善レバー（いずれも十分高速のまま）: **句読点モデル追加**、**decodingMethod=modified_beam_search**、**fp32 encoder**（RTF 0.082）。
- 配置の弱点: dev では adb 手動配置＋ホットリスタート運用。本番化時は「初回DL（tar.bz2 680MB→必要分抽出 or ミラー）」の UX 設計が要る。

→ **速度・体験は sherpa-onnx ja が現状ベスト**。残る比較は Vosk（真のストリーミング＝話しながら逐次表示・ただし精度は低め）。

### B-2 比較対象その2: Vosk（真のストリーミング）実測（2026-06-14）

`vosk_flutter_service`（permission_handler ^12 互換。`vosk_flutter`/`vosk_flutter_2` は ^10/^11 依存で本プロジェクトと衝突）で実装。新セクション `vosk (streaming ja)`。Vosk 自身がマイク＋無音区切りを担当（**VAD 不使用**）。モデルは `ModelLoader.loadFromNetwork` で `vosk-model-small-ja-0.22`（約48MB zip）を**自動DL＆解凍**（adb 不要・キャッシュ＆自己回復）。`SpeechService.onPartial()`（逐次）/`onResult()`（確定）。ビルドは alphacephei maven の `vosk-android:0.3.75` AAR を取得（`libc++_shared.so` は pickFirst 済みで重複回避）。

実測（確定テキスト）:
| seg | 確定テキスト |
|---|---|
| 3 | めちゃくちゃ すぐ に 者 が 出 て くる でしょ これ 完全 に ストリーミング みたい な 感じ だ |
| 4 | は これ すごい ぞ |
| 5 | は 精度 が 確か に も 来 ない けど |
| 7 | 早い |

- **真のストリーミング体験は実現**（話している最中に「逐次テキスト」が更新され、止まると確定）。「話しながら出る」感は唯一。
- ただし **精度は明確に低い**：単語が空白で分かち書きされ不自然、誤認識も多い（「字」→「者」等）。日本語メモ用途では読み返しに難。

### B-2 追加検証: sherpa NeMo parakeet CTC 0.6B（高精度版）実測（2026-06-14）

同じ ReazonSpeech データの **NeMo系（FastConformer・0.6B）** を sherpa-onnx で追加検証。これは k2 Zipformer(159M) の“大型・高精度”兄弟。配布は `sherpa-onnx-nemo-parakeet-tdt_ctc-0.6b-ja-35000-int8`（HF に個別ファイルあり：`model.int8.onnx` 約625MB ＋ `tokens.txt`）。**CTC方式**なので sherpa の `nemoCtc`（単一ファイル）config を使う。観察セクションに「モデル選択（Zipformer / NeMo CTC）」ドロップダウンを追加。

実測:
| seg | 音声長 | 転写時間 | 結果 |
|---|---|---|---|
| seg#1 | 2.3s | 197ms | 話しかけてみますけど |
| seg#2 | 1.4s | 128ms | これでどうなりますかね。 |
| seg#3 | 3.7s | 276ms | 結構自分の声がうまく入ってるような気もするが |
| seg#4 | 1.4s | 117ms | お結構いいな。 |
| seg#6 | 1.9s | 150ms | これが一番いいような気がしてきた。 |
| seg#7 | 2.3s | 176ms | うんうんうんじゃあこれにするか |

- **速度 108〜276ms**（音声長に比例）。k2 Zipformer(~50ms) より2〜5倍遅いが、**whisper(~4秒) より15〜40倍速く、体感は「話し終えて即」で変わらない**。
- **精度はオンデバイス中ベスト**。日本語が自然で、**句読点「。」が付く**（Zipformer の弱点を解消）。フィラー「うんうんうん」も拾う。
- 代償は**サイズ（625MB）とメモリ**。Pixel 8a では問題なく動作（クラッシュなし）。

### B-2 最終結論（全エンジン/モデル比較）

| エンジン/モデル | 文字が出る | 日本語精度 | テキストの綺麗さ | モデルサイズ | 体験 |
|---|---|---|---|---|---|
| whisper small-q5_1（B-1） | 話し終えて ~4秒 | 高 | 綺麗（句読点あり） | 181MB | 遅すぎ |
| base-q5_1 | ~4秒 | 低 | 崩れ多 | 57MB | ギリギリ |
| sherpa k2 Zipformer (159M) | **~50〜140ms** | 中〜やや高 | 自然（句読点なし） | 160MB | 即・最速 |
| **sherpa NeMo parakeet CTC (0.6B)** | **~110〜280ms** | **最高** | **自然＋句読点** | **625MB** | **即・最高精度** |
| Vosk small-ja | 話しながら逐次 | 低 | 粗い（分かち書き） | 48MB | ライブ感は唯一だが粗い |

- **総合ベストは sherpa NeMo parakeet CTC 0.6B**：精度トップ＋句読点付き＋体感ゼロ遅延（~150ms）。whisper は速度で全く敵わず、精度面の優位も無くなった。
- **軽さ最優先なら sherpa k2 Zipformer(160MB)**：精度は一段落ちる（句読点なし）が最速・最小。
- **「話しながら出る」ライブ表示が要るなら Vosk** だが精度は最下位。
- → **本番採用は sherpa-onnx。モデルは「精度重視＝NeMo CTC(0.6B)」「サイズ重視＝k2 Zipformer(160MB)」の二択**。最大の残課題は **NeMo の 625MB をどう配布するか**（初回DLのUX設計）。

---

## 8. 多言語対応の見通し（sherpa / Vosk, 2026-06-14）

将来の言語拡張（英・中・仏 等）の観点。**両エンジンとも多言語対応は可能**で、アプローチが異なる。

### Vosk — 40言語以上（言語ごとに1モデル）
- モバイル向け小モデルが言語別にある: 英40MB / 中42MB / 仏41MB / 独45MB / 西39MB / 露45MB / 韓82MB ほか、伊・葡・蘭・アラビア・トルコ・越・ヒンディー等 **40言語以上**。
- 実装的に最も手軽: このセクションは `loadFromNetwork(URL)` の URL を差し替えるだけで言語を切替できる。
- 補足: 今回 Vosk 日本語で見えた「分かち書き（空白区切り）」は**日本語特有**。英・仏など元々スペース区切りの言語では正常な出力で、学習資源が多い分 精度も日本語小モデルより出やすい。

### sherpa-onnx — 多言語モデルを使い分け
| モデル | 対応言語 | 特徴 |
|---|---|---|
| **SenseVoice** | 中・英・日・韓・広東語（5言語を1モデル） | 高速・オフライン。日本人の「日+英」を1モデルで賄える |
| **Canary**（NVIDIA） | 英・独・西・仏（4言語） | 欧州系をカバー。翻訳も可 |
| 専用 transducer | 日(ReazonSpeech)・英・中・韓 等 | 言語ごとに最高精度（今回の日本語がこれ） |
| Whisper（sherpa上で実行） | 99言語 | 全言語網羅だが遅い（30秒枠問題） |

### momeo への示唆
- 日本語主体 → 今の **sherpa ja（ReazonSpeech）**。
- 日+英を1モデル → **sherpa SenseVoice**。
- 欧州系まで → **sherpa Canary** か **Vosk 言語別**（URL差し替えで最も手軽・40言語超）。
- → どちらも将来の多言語化は可能。**本番結線時は「エンジン／モデルを差し替え可能な抽象」で組む**のが望ましい（まず sherpa ja、後で SenseVoice 等へ差し替えられる構造）。

参考: [Vosk models](https://alphacephei.com/vosk/models) ／ [sherpa SenseVoice](https://k2-fsa.github.io/sherpa/onnx/sense-voice/index.html) ／ [sherpa 事前学習モデル一覧](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/index.html)

---

## 付録: 確認に使った事実とコマンド

- **端末のモデル確認**: `adb shell run-as jp.momeo.momeo ls -la files/whisper_models/`
- **HuggingFace の実サイズ確認**: `curl -sIL "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"` → 302（Xet CDN）→ 200 `Content-Length: 487601967`
- **ネイティブ実装**: `~/.pub-cache/hosted/pub.dev/whisper_flutter_new-1.0.1/src/main.cpp`（毎回 `whisper_init_from_file` → `whisper_free`）, `src/CMakeLists.txt`（CPU専用ビルドフラグ）, `src/whisper.cpp/ggml.h`（量子化型サポート）
- **クラッシュ**: `Fatal signal 11 (SIGSEGV) ... fault addr 0x180`（null deref）in `libwhisper.so`、原因は破損モデル（4,616,436 B / 正常 487,601,967 B）
