# Step 5: 録音した音を「発話ごと」に区切る（VAD）

## ひとことで言うと

Step 3 で取れるようになった「マイクの音（PCM）」を sherpa 内蔵の VAD に流し込み、
**「ここからここまでが1回の発話」と区切って取り出せる**ようにするステップ。まだ文字にはしない。

dev catalog には、区切りの設定値を**スライダーで調整しながら区切り具合を確認できる**セクションを置き、製品版の設定値もここで詰める。

---

## このステップの目的

全体の流れの中で、このステップは「区切り」を担当する。

```
マイク → 録音 → 区切り → 文字化 → メモに保存
                 ↑
                 ここ
```

ずっと録音し続けた音には無音や間が混ざる。まるごと文字化に渡すより、**「1回しゃべったぶん」だけを切り出してから**渡した方が、扱いやすく精度も上がる。

その切り出しをするのが **VAD**（Voice Activity Detection ＝ 音の中から「人が話している部分」を見つけ、発話の始まり・終わりで区切る仕組み）。このアプリでは Step 4 で入れた **sherpa_onnx 内蔵の VAD（Silero VAD）** を使う。

**このステップで必要なモデルは `silero_vad.onnx`（約0.6MB）だけ。** 文字化用の NeMo（約625MB）は要らないので、配布の難所（Step 6）はまだ考えなくてよい。

---

## 区切りの長さ ＝ あとで「カードの分かれ方」になる

ここが Step 5 の肝。後の Step 10 では「**1つの発話チャンク = メモカード1枚**」としてつなぐ。
つまり**ここで区切る長さが、そのままカードの分かれ方になる**。短く区切りすぎると、ひと続きのつもりの発話が細切れのカードに割れてしまう。

区切りの**主役は「間（無音）」**。1.5秒ほど黙ったら発話の終わりとみなす。だから普通に長く話しても、文の切れ目で間が空けばそこで区切られ、間を空けずに続けるかぎり同じカードに入る。

区切り具合は、VAD の次のパラメータで決まる。dev catalog でこれらを調整しながら、自然な長さで区切れる値を見つける。

| パラメータ | 役割 | カードへの影響 | 初期値 |
|---|---|---|---|
| `minSilenceDuration` | **主役**：何秒 静かになったら発話終了とみなすか | **大きいほど**細切れにならず、カードが長く・少なくなる | **1.5秒**（※1） |
| `minSpeechDuration` | これより短い音は発話と認めない | 短いノイズをカードにしない | 既定から |
| `maxSpeechDuration` | **安全弁**：一度も間を空けず話し続けた時だけ、強制的に区切る上限 | 暴走（黙らず喋り続ける）を止めるだけで、普段は効かない | **30秒**（※2） |

- ※1 `minSilenceDuration` の初期値 1.5秒は、[docs/specs/listening_flow.md](../specs/listening_flow.md) の「無音が1.5秒続いたら発話終了」という製品意図に合わせたもの。
- ※2 `maxSpeechDuration` は安全弁なので長めにとり、初期値は **30秒**（スライダー上限）にしている。普段の区切りは主役の `minSilenceDuration` が担うため、ここに達するのは「黙らず喋り続けた」例外時だけ。30秒の発話を余裕で収めるため、VAD のバッファ（`bufferSizeInSeconds`）は **60秒**にしている。いずれも実機で調整する。

---

## やること

### 1. 区切りの仕組み（箱）を作る

「マイクの音を入れたら、発話チャンクが出てくる箱」を作る。箱の中でやることは3つ。

1. **音の数値を VAD が読める形に直す**：`record` の音は整数（PCM16）だが、VAD は小数（Float32）で受け取る。`整数 ÷ 32768` で小数に変換する（音の中身は同じで、数字の表し方を変えるだけ）。
2. **決まった量ずつ VAD に渡す**：VAD は 512サンプル（ごく短い一定量）ずつしか受け取らないので、音をその量ためては渡す、を繰り返す。
3. **区切れた発話を取り出す**：VAD が「1発話ぶん終わった」と判断したものを、順に取り出す。

（それぞれの具体的な呼び出しは「実装メモ」を参照）

この箱は最終的に本番（Step 10 のリスニング画面）でも使うが、**まずは検証セクション内に書いて動かす**。本番で必要になった時（Step 10）に小さなクラスへ切り出す。最初から共通化を作り込まない（可読性優先）。

### 2. VAD モデル（silero_vad.onnx）を配置する

sherpa は「実ファイルのパス」からしかモデルを読めない。そこで `silero_vad.onnx`（約0.6MB）を **Flutter の普通のアセットとして同梱**し、初回に端末の書き込み可能領域へコピーして、その実パスを VAD に渡す。

モデルは sherpa-onnx 公式の配布物（`asr-models` リリース）から取得し、`assets/models/silero_vad.onnx` に置く。

```bash
curl -fSL -o assets/models/silero_vad.onnx \
  https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx
```

0.6MB と小さいので **iOS / Android で実装は同じ**（アセット読み込み ＋ `path_provider` でのコピー）。大容量モデル用の Android 対応（PAD）は不要で、最終製品での silero 配置（Step 6 の初回コピー）とも同じやり方になる。

### 3. dev catalog に検証セクション（調整 UI）を追加する

新しく「**STT**」グループを作り、その中に検証セクションを置く。

- 既存の「Packages」は `record` / `sherpa_onnx` の**単体チェック**用。Step 5 以降の「区切り」「文字化」という**パイプラインの工程の検証**は「STT」にまとめ、録音→区切り→文字化の順に並べる。
- 新規ファイル: `lib/pages/dev/catalog/sections/stt/stt_vad_section.dart`
- 内容: **録音 開始/停止** ＋ **3つのパラメータをスライダーで調整** ＋ **区切られた発話チャンクの件数・長さ（秒）を表示**。
- 値を変えたら VAD を作り直し、その場で区切り具合を確かめられる（製品版の値の研究もここで行う）。

このスライダー UI は **dev 専用の研究ツール**で、製品には持ち込まない（製品は調整後の固定値を使う）。

---

## このステップでやらないこと

- 発話チャンクを**文字にする** → Step 7
- 大きい NeMo モデルの**配置・配信** → Step 6（配置）・Step 8（Android fast-follow）
- リスニング画面への**本配線**（チャンク → カード） → Step 10

---

## 完了の目安

- dev catalog の検証セクションで録音すると、話すたびに**発話チャンクが1件ずつ増える**。
- 各チャンクの長さ（秒）が表示され、しゃべった長さと大きくずれない。
- スライダーで `minSilenceDuration` 等を変えると区切り具合が変わり、**不自然に短く割れない**値を見つけられる。
- `silero_vad.onnx` がアセットから配置され、VAD が読み込めている。
- `flutter analyze` が通る。

---

## 実装メモ（sherpa VAD の使い方）

実証済み（spike）の流れ。実装時の参照用。

- **VAD の生成**:
  `VoiceActivityDetector(config: VadModelConfig(sileroVad: SileroVadModelConfig(model: <パス>, minSilenceDuration: ..., minSpeechDuration: ..., maxSpeechDuration: ...), sampleRate: 16000), bufferSizeInSeconds: 60)`
  - `windowSize` は既定 512（16kHz の Silero 用）。この単位で音を渡す。
  - パラメータは生成時にしか効かないので、**変えるときは古い VAD を `free()` して作り直す**（silero は軽いので一瞬）。
- **音を渡す**: PCM16 →（÷32768 で）Float32 に変換し、**512サンプルずつ** `vad.acceptWaveform(window)`。
- **区切りを取り出す**:
  ```
  while (!vad.isEmpty()) {
    final segment = vad.front(); // SpeechSegment（samples: Float32List, start: 開始位置）
    vad.pop();
    // segment.samples が1発話分の音。長さ(秒) = samples.length / 16000
  }
  ```
- **録音停止時**: `vad.flush()` してから取り出すと、末尾に残った発話も押し出せる。
- **後始末**: 使い終わったら `vad.free()`。録音開始時は `vad.clear()` で前回分を消す。

---

## 作業チェックリスト

- [ ] `silero_vad.onnx`（約0.6MB・sherpa-onnx 公式 `asr-models`）を `assets/models/` に置き、`pubspec.yaml` の assets に登録
- [ ] 初回にアセットを端末の読める場所へコピーする処理
- [ ] PCM16 → Float32 変換と、512サンプル窓での VAD 供給
- [ ] 発話チャンクの取り出し（isEmpty / front / pop / flush）
- [ ] dev catalog「STT」グループに `stt/stt_vad_section.dart` を追加（スライダー ＋ 件数・長さ表示）
- [ ] 初期値を設定（`minSilenceDuration` 1.5秒〔specs 由来〕／`maxSpeechDuration` 30秒〔安全弁〕／VAD バッファ 60秒）
- [ ] 実機で「自然な長さで1件ずつ区切られる」ことを確認しつつ値を調整
- [ ] `flutter analyze` が通る
