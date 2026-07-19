# GitHub Pages でのサイト公開手順(momeo.jp)

ストア公開([store_release_plan.md](../store_release_plan.md) Phase 0)に必要な
プライバシーポリシーページとサポートページを、GitHub Pages で momeo.jp に公開するまでの手順。
方法の選定経緯は [privacy_policy_hosting.md](privacy_policy_hosting.md) を参照。

## 前提

| 項目 | 内容 |
|---|---|
| リポジトリ | `NobuyukiMorii/momeo`(既存・public) |
| 公開方式 | **main ブランチの `/docs` フォルダ**(Deploy from a branch) |
| ドメイン | momeo.jp(お名前.com 取得済み。ネームサーバーもお名前.comのまま) |
| 費用 | 無料(public リポジトリのため) |

開発ドキュメントは `notes/` に置く。`docs/` は公開サイト専用のフォルダで、
中身がそのまま `https://momeo.jp/` のドキュメントルートになる。
ページは HTML を置いた分だけ公開されるので、将来のランディングページ等も同じ枠で増やせる。
ブランチ分離や GitHub Actions のワークフローは不要で、普段どおり main に push するだけでよい。

## 全体の流れ

1. `docs/` フォルダに HTML ページを置いて push する
2. GitHub の Settings → Pages で公開設定をする
3. カスタムドメイン momeo.jp を設定する
4. お名前.com で DNS(A レコード)を変更する
5. HTTPS を有効化し、表示を確認する

---

## 1. ページの作成

main ブランチに `docs/` フォルダを作り、最低限、次の 3 ファイルを置く。

```
docs/
├── index.html      # トップ(当面はアプリ紹介 + サポート・連絡先への導線)
├── privacy.html    # プライバシーポリシー
└── support.html    # サポート・連絡先
```

- URL は `docs/` を除いたパスがそのまま対応する:
  `docs/privacy.html` → `https://momeo.jp/privacy.html`
- プライバシーポリシーの記載の柱(store_release_plan.md Phase 0 のとおり):
  - マイク音声はオンデバイスで処理し、外部に送信しない
  - メモは端末内にのみ保存される
  - 個人情報の収集なし
  - 連絡先
- App Store の申請ではサポート URL が必須項目のため、`support.html` に
  連絡先(メールアドレス)を必ず記載する

作成したら commit して main に push する。

```bash
git add docs/
git commit -m "Add site pages for momeo.jp"
git push
```

## 2. Pages の公開設定

GitHub のリポジトリページで設定する。

1. **Settings → Pages** を開く
2. Build and deployment の Source: **Deploy from a branch**
3. Branch: **main** / **/docs** を選んで Save

保存すると自動でデプロイが走り、まず `https://nobuyukimorii.github.io/momeo/` で公開される。

## 3. カスタムドメインの設定

1. 同じ Settings → Pages の **Custom domain** に `momeo.jp` を入力して Save
2. `docs/` 直下に `CNAME` ファイルが自動でコミットされる
   (手元で作業を続ける前に `git pull` すること)

この時点では DNS がまだ向いていないため、DNS check はエラーのままでよい。

## 4. お名前.com の DNS 変更

お名前.com の「ネームサーバーの設定 → DNS レコード設定」で行う。
ネームサーバー自体(`dns1/dns2.onamae.com`)は変更しない。

> メールアドレス(`support@momeo.jp`)のためにネームサーバーを Cloudflare へ
> 移管する場合([cloudflare_email_setup.md](../email/cloudflare_email_setup.md))は、
> 本章のレコード追加をお名前.com ではなく Cloudflare の DNS 画面で行う(内容は同じ)。

1. **パーキング用の既存 A レコード(150.95.255.38)を削除する**
2. GitHub Pages の固定 IP へ向ける A レコードを 4 つ追加する:

   | ホスト名 | TYPE | VALUE |
   |---|---|---|
   | (空 = momeo.jp) | A | 185.199.108.153 |
   | (空 = momeo.jp) | A | 185.199.109.153 |
   | (空 = momeo.jp) | A | 185.199.110.153 |
   | (空 = momeo.jp) | A | 185.199.111.153 |

3. `www` 用の CNAME レコードを 1 つ追加する:

   | ホスト名 | TYPE | VALUE |
   |---|---|---|
   | www | CNAME | nobuyukimorii.github.io |

   GitHub Pages は apex ドメイン(momeo.jp)を設定すると `www` 付きの URL も
   自動で検証するため、この CNAME がないと DNS check が
   「www.momeo.jp is improperly configured (InvalidDNSError)」のままになり、
   証明書も発行されない。VALUE はユーザー名のみで、リポジトリ名(`/momeo`)は付けない。

レコードは上記の A レコード 4 つ + CNAME 1 つの計 5 つ。

反映確認は次のコマンドで行う(A は 185.199.108〜111.153、
www は nobuyukimorii.github.io が返れば OK)。

```bash
dig momeo.jp +noall +answer
dig www.momeo.jp +noall +answer
```

## 5. HTTPS の有効化と確認

1. DNS 反映後、Settings → Pages の DNS check が通ると
   Let's Encrypt 証明書が自動発行される(数分〜数時間)
2. **Enforce HTTPS** にチェックを入れる
3. 次の URL が表示されることを確認する:
   - `https://momeo.jp/`
   - `https://momeo.jp/privacy.html`
   - `https://momeo.jp/support.html`
4. ストア申請フォームに記載する:
   - プライバシーポリシー URL: `https://momeo.jp/privacy.html`(両ストア必須)
   - サポート URL: `https://momeo.jp/support.html`(App Store 必須)

DNS の反映と証明書発行に最大で数時間〜1日かかることがあるため、
申請作業より前(Phase 0 のうち)に済ませておく。

---

## 公開後の更新方法

サイトの更新は `docs/` 内のファイルを編集して main に push するだけ。
push から 1 分前後で反映される。アプリ開発と同じフローで完結する。

## 注意事項

- **`docs/` に置いたファイルはすべて momeo.jp で公開される**。
  内部向けのメモ・ドキュメントは必ず `notes/` に置くこと
- `docs/CNAME` ファイルを消すとカスタムドメイン設定が外れるので削除しない
- 制限はサイト 1GB・帯域 100GB/月(ソフトリミット)。本用途では問題にならない
- サーバーサイド処理(フォーム受信・DB・API)は不可。問い合わせフォームが
  必要になったら Google Forms 等へのリンクで対応する
