# アプリアイコンの作り方（iOS / Android）

momeo のアプリアイコンを、Figma での画像作成から端末のホーム画面に表示されるまで、
この1枚だけ見れば作業できるようにまとめる。

先に結論:

- **Figma で 1024×1024 の PNG を2枚作るだけでよい**（iOS 用1枚 + Android 用1枚）
- サイズ違いのファイルを手で量産する必要はない。
  `flutter_launcher_icons` というツールが全サイズを自動生成してくれる

---

## 0. 最初に知っておくこと（ここだけ読めば迷わない）

### iOS と Android ではアイコンの渡し方が違う

| | iOS | Android |
|---|---|---|
| 渡すもの | 完成した画像 **1枚** | ロゴだけの画像 ＋ 背景色の **2層** |
| 角の切り抜き | OS が自動で角丸にする | OS が端末ごとの形（丸・角丸四角など）にする |

### 用語の意味

- **フルブリード**
  「キャンバスの端まで絵で埋め尽くす」こと。余白なし・角丸なし・透明部分なし。
  iOS は表示時に OS が勝手に角を丸く切り抜くので、こちらは角まで塗った
  ただの四角い画像を渡せばよい。逆にこちらで角を丸めてしまうと、
  OS の角丸と二重になって四隅に隙間が見えてしまう。

- **前景（foreground）／背景（background）**
  Android 8.0 以降のアイコン（アダプティブアイコン）は、画像を2枚のレイヤーに
  分けて渡す仕組み。
  - 背景 = 一番下に敷く層。単色でよい（momeo は色コード指定だけで済ませる）
  - 前景 = その上に重ねる層。**ロゴだけ**を描き、それ以外は透明にした PNG

  分ける理由は、Android は端末メーカーごとにアイコンの形が違うため。
  OS が2枚を重ねたあと、端末ごとの形に切り抜いて表示する。

- **セーフゾーン**
  Android の前景画像のうち、どんな形に切り抜かれても確実に残る中央部分のこと。
  1024×1024 なら **中央の直径 66%（約 660px）の円の内側**。
  ロゴはこの中に収める。外周は切り抜きで欠ける可能性があるので何も置かない。

---

## 1. Figma で画像を2枚作る

momeo の Figma ファイル: `ErddJebG6AfGqaGTCKfDuk`

どちらも **1024×1024 px のフレーム**で作る。

### ① iOS 用（1枚に焼き込んだ完成画像）

- 背景色を全面に敷き、その上にロゴを置く（＝フルブリード）
- 角丸・余白・影は付けない（OS が自動で付けるため）
- 透明部分を残さない（iOS のアイコンは不透明が必須）
- ロゴは端に寄せすぎず、中央に少しゆとりを持たせると見栄えがよい

### ② Android 前景用（ロゴのみ・背景透明）

- フレームの塗り（Fill）を外して背景を透明にする
- ロゴを **中央の直径 660px の円の内側**（セーフゾーン）に収める
  - 目安: Figma で 660×660 の円を中央にガイドとして置き、
    ロゴがはみ出していないか確認してから円を消す

Android の背景は白一色にするので、画像は作らない（後の設定で色コード `"#FFFFFF"` を書くだけ）。
グラデーションや模様を敷きたくなった場合のみ、3枚目として背景画像を作る。

---

## 2. Figma から PNG で書き出す

1. フレームを選択する
2. 右パネル最下部の **Export** で以下を設定して Export ボタンを押す
   - フォーマット: **PNG**
   - 倍率: **1x**（フレームがすでに 1024px あるため）
3. 書き出した2枚を、リポジトリの次の場所に置く

```
assets/
  icon/
    app_icon_ios.png            # ① iOS 用（背景焼き込み・不透明）
    app_icon_android_fg.png     # ② Android 前景（透明・ロゴは中央66%以内）
```

> `assets/icon/` はアイコンの「元画像」を置くだけの場所。
> ここに置いた画像がそのまま端末に入るわけではなく、次の手順の生成に使われる。
> アプリ本体に同梱する必要はないので、`pubspec.yaml` の `flutter: assets:` への登録は不要。

---

## 3. 自動生成ツールを設定する

### 3-1. パッケージを追加する

ターミナルでプロジェクトルートに移動して実行:

```bash
flutter pub add --dev flutter_launcher_icons
```

`dev_dependencies`（開発時だけ使う道具）として追加される。アプリ本体には含まれない。

### 3-2. `pubspec.yaml` に設定を書く

`pubspec.yaml` の末尾（インデントなしのトップレベル）に以下を追加する。

```yaml
flutter_launcher_icons:
  # iOS と、Android の旧来型単一アイコンの両方に使われるベース画像
  image_path: "assets/icon/app_icon_ios.png"

  # iOS
  ios: true
  remove_alpha_ios: true        # 万一透明が残っていても自動で除去してくれる保険

  # Android（アダプティブアイコン）
  android: true
  adaptive_icon_background: "#FFFFFF"                             # 背景 = 白一色
  adaptive_icon_foreground: "assets/icon/app_icon_android_fg.png" # 前景 = ロゴのみ
```

背景を画像にしたい場合だけ、`adaptive_icon_background` を色コードの代わりに
画像パス（例 `"assets/icon/app_icon_android_bg.png"`）にする。

---

## 4. 生成コマンドを実行する

```bash
dart run flutter_launcher_icons
```

> 古い記事では `flutter pub run flutter_launcher_icons:main` と書かれていることがあるが、
> 今は上のコマンドでよい。

これで iOS / Android の全サイズが自動生成され、以下のディレクトリが上書きされる。
**すべて生成物なので、手で編集しない。**

iOS の生成先:

```
ios/Runner/Assets.xcassets/AppIcon.appiconset/
  Icon-App-20x20@1x.png … Icon-App-1024x1024@1x.png   # 全サイズ
  Contents.json                                        # サイズの対応表
```

Android の生成先:

```
android/app/src/main/res/
  mipmap-mdpi/ic_launcher.png       # 画面密度ごとの単一アイコン
  mipmap-hdpi/ic_launcher.png
  mipmap-xhdpi/ic_launcher.png
  mipmap-xxhdpi/ic_launcher.png
  mipmap-xxxhdpi/ic_launcher.png
  mipmap-anydpi-v26/ic_launcher.xml # アダプティブアイコン定義
  values/colors.xml                 # 背景色を色コードで指定した場合
```

> 補足: momeo の現状の Android アイコンは旧来型（単一 `ic_launcher.png`）のみで、
> アダプティブアイコンになっていない。上の設定で生成すればアダプティブアイコン用の
> ファイル一式も新しく作られる。

---

## 5. 実機・シミュレータで確認する

```bash
flutter clean
flutter pub get
flutter run
```

確認ポイント:

- **iOS**: ホーム画面で角丸が正しく付き、ロゴの余白バランスが崩れていないか
- **Android**: ホーム画面でロゴが欠けていないか
  （端末やランチャー設定によって丸・角丸四角など形が変わるので、
  形を変えて見られる環境があれば複数の形で確認する）

### ストア用アイコンについて

App Store / Google Play のストア掲載ページに表示されるアイコン（1024×1024）は、
アプリに埋め込むものではなく、**ストア登録時に別途アップロードする**。
手順1で作った iOS 用の画像（`app_icon_ios.png`）をそのまま使えばよい。

---

## 付録: 自動生成されるサイズの一覧（参考）

ツールを使えば意識する必要はないが、仕組みの理解のために載せておく。

### iOS

| 用途 | 実ピクセル |
|---|---|
| iPhone 通知 20pt | 40 / 60 |
| iPhone 設定 29pt | 58 / 87 |
| iPhone Spotlight 40pt | 80 / 120 |
| iPhone アプリ 60pt | 120 / 180 |
| iPad アプリ 76pt | 76 / 152 |
| iPad Pro 83.5pt | 167 |
| App Store | 1024 |

### Android（画面密度別 `ic_launcher`）

| 密度 | 単一アイコン | アダプティブ（全体） |
|---|---|---|
| mdpi | 48 | 108 |
| hdpi | 72 | 162 |
| xhdpi | 96 | 216 |
| xxhdpi | 144 | 324 |
| xxxhdpi | 192 | 432 |

アダプティブアイコンは全体 108dp のうち内側 72dp がセーフゾーンで、
外周 18dp ずつは切り抜きで欠ける前提で設計されている。
