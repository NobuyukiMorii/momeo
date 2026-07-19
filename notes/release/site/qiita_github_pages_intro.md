## 概要

個人でスマホアプリを作っています。

いざストアに公開しようとすると、アプリ本体とは別に**Webページ**が必要になります。

- プライバシーポリシーページ（App Store・Google Play どちらも URL の記載が必須）
- サポートページ（App Store はサポート URL が必須）
- ついでに、アプリ紹介のトップページも欲しい

中身はただの静的HTMLが数枚。なのに、このためだけに S3 + CloudFront を組んだり、Netlify に新しいプロジェクトを作ったりするのは、正直面倒ですよね。デプロイの仕組みがひとつ増えるし、アプリ本体とは別の場所に「管理するもの」が生まれてしまいます。

**アプリのリポジトリの中で、ソースコードと一緒に管理できたら最高では？**

これ、GitHub Pages の「/docs フォルダ公開」でできました。無料・独自ドメイン対応・HTTPS自動・デプロイは `git push` するだけです。

同じ状況の個人開発者は多いと思うので、手順をまとめます。

前提として、独自ドメイン（この記事では `example.jp` とします）は取得済みの状態からスタートします。DNS の管理画面が使えれば、Cloudflare でもお名前.com でもやることは同じです。

## 仕組み

リポジトリはこうなります。

```text
your-app/           # アプリのリポジトリ（public）
├── lib/            # アプリのソースコード
├── ios/ android/   # （など、いつものアプリの中身）
└── docs/           # ← このフォルダがそのまま https://example.jp/ になる
    ├── index.html      # → https://example.jp/
    ├── privacy.html    # → https://example.jp/privacy.html
    └── support.html    # → https://example.jp/support.html
```

`docs/` の中身が、そのまま公開サイトのドキュメントルートになります。

- 公開・更新は main ブランチに **push するだけ**（1分前後で反映）
- ブランチ分離も GitHub Actions のワークフローも不要
- 「プライバシーポリシーの文言を直した」というコミットが、アプリの履歴と同じ場所に残る

アプリ開発と完全に同じフローでサイトも回るのが、この方式の一番うれしいところです。

## ほかの方法と比べてどうなの？

一応、ほかの選択肢も調べました。

| 方法 | 費用 | ひとこと |
|---|---|---|
| GitHub Pages（/docs 公開） | **無料** | 今回の方法。アプリのリポジトリ内で完結 |
| S3 + CloudFront | ほぼ無料 | apex ドメイン（example.jp）対応には CloudFront + ACM が必要で、静的3ページには大げさ |
| Netlify / Vercel | 無料 | 十分アリ。ただしアプリとは別のサービス・別プロジェクトが増える |
| Firebase Hosting | 無料 | 同上。デプロイコマンドもアプリとは別系統になる |

「静的ページが数枚」「apex ドメインで公開したい」「管理するものを増やしたくない」という条件なら、GitHub Pages 一択でした。

なお、GitHub Pages が無料なのは **public リポジトリの場合**です。アプリのリポジトリが private の場合は有料プラン（Pro 以上）が必要になるので、そこだけ注意してください。

## 全体の流れ

1. `docs/` フォルダに HTML を置いて push する
2. GitHub の Settings → Pages で公開設定をする
3. カスタムドメインを設定する
4. DNS レコードを追加する
5. HTTPS を有効化して表示を確認する

順番に見ていきます。

## 📌 ステップ1：docs/ フォルダにページを置く

main ブランチに `docs/` フォルダを作り、HTML を置きます。最低限この3枚です。

| ファイル | 公開URL | 内容 |
|---|---|---|
| `docs/index.html` | `https://example.jp/` | トップ（アプリ紹介 + 各ページへの導線） |
| `docs/privacy.html` | `https://example.jp/privacy.html` | プライバシーポリシー |
| `docs/support.html` | `https://example.jp/support.html` | サポート・連絡先 |

サポートページには連絡先のメールアドレスを載せます（App Store の申請で必須です）。個人の Gmail を晒したくない場合は、`support@自分のドメイン` を無料で作る方法を前回の記事にまとめたので、そちらをどうぞ。（TODO: 公開後にメール記事のリンクを貼る）

書けたら commit して push します。

```bash
git add docs/
git commit -m "Add site pages"
git push
```

⚠️ ひとつだけ注意。**`docs/` に置いたファイルは全部公開されます**。開発メモや設計ドキュメントを `docs/` に置く習慣がある場合は、`notes/` など別のフォルダに逃がしておきましょう。

## 📌 ステップ2：Pages の公開設定

GitHub のリポジトリページで設定します。

1. **Settings → Pages** を開く
2. Build and deployment の Source: **Deploy from a branch**
3. Branch: **main** / **/docs** を選んで **Save**

<!-- TODO: スクリーンショット（Settings → Pages の Build and deployment 設定） -->

これだけで自動でデプロイが走り、まず `https://ユーザー名.github.io/リポジトリ名/` で公開されます。

## 📌 ステップ3：カスタムドメインの設定

同じ Settings → Pages の **Custom domain** に `example.jp` を入力して Save します。

<!-- TODO: スクリーンショット（Custom domain 入力欄） -->

Save すると、GitHub が **`docs/CNAME` というファイルをリポジトリに自動でコミット**します。リモートに自分の知らないコミットが増えるので、手元で作業を続ける前に `git pull` しておきましょう（僕はこれを知らずに、次の push のときに「なんかリモートに知らないコミットがある…？」と一瞬混乱しました）。

この時点では DNS がまだ向いていないので、DNS check がエラーになりますが、それで正常です。次のステップで解決します。

## 📌 ステップ4：DNS レコードの追加

ドメインの DNS 管理画面で、レコードを **5つ** 追加します。僕は Cloudflare で管理していますが、お名前.com のままなら「DNSレコード設定」で同じ内容を追加すればOKです。

| Type | Name | Content |
|---|---|---|
| A | `@` | 185.199.108.153 |
| A | `@` | 185.199.109.153 |
| A | `@` | 185.199.110.153 |
| A | `@` | 185.199.111.153 |
| CNAME | `www` | `（GitHubユーザー名）.github.io` |

<!-- TODO: スクリーンショット（DNSレコード追加後の一覧） -->

A レコードの4つは GitHub Pages の固定IPです。CNAME の値は**ユーザー名のみ**で、リポジトリ名（`/your-app`）は付けません。

Cloudflare の場合はもうひとつ。プロキシは必ず **DNS only（グレーの雲）** にしてください。Proxied（オレンジの雲）にすると、GitHub の DNS 検証と証明書発行が通らなくなります。

### 反映の確認

dig で確認できます。A レコード4つと、www の CNAME が返ってくればOKです。

```bash
dig example.jp +noall +answer
dig www.example.jp +noall +answer
```

DNS が引けるようになったら、GitHub の Settings → Pages に戻って、エラーボックスの「**Check again**」を押します。GitHub は前回のチェック結果をキャッシュしているので、DNS を直しても**自動ではすぐ再判定してくれません**。「DNS check successful」になれば成功です（1回で通らなければ、数分おいてもう一度）。

## 📌 ステップ5：HTTPS の有効化と表示確認

DNS check が通ると、Let's Encrypt の証明書が自動で発行されます（数分〜1時間程度）。

発行されると Settings → Pages の **Enforce HTTPS** にチェックを入れられるようになるので、チェックを入れます。これで `http://` へのアクセスも `https://` にリダイレクトされます。

最後に表示確認です。

- `https://example.jp/`
- `https://example.jp/privacy.html`
- `https://example.jp/support.html`

ストアの申請フォームには、この `privacy.html` と `support.html` の URL をそのまま書けばOKです。

## 公開後の更新

`docs/` 内のファイルを編集して push するだけです。1分前後で反映されます。

アプリのコードを直すのとまったく同じフローなので、「サイトの更新方法を思い出す」というコストがゼロなのが本当に楽です。

## 制限と注意

- サイズはサイト全体で 1GB、帯域は月 100GB のソフトリミット。静的ページ数枚なら一生届きません
- サーバーサイド処理（フォーム受信・DB・API）は不可。問い合わせフォームが必要になったら Google Forms 等へのリンクで対応
- `docs/CNAME` を消すとカスタムドメイン設定が外れるので、削除しないこと

## まとめ

👉 **アプリのリポジトリに `docs/` を足して push するだけで、独自ドメインの公式サイトが無料で手に入りました** ❤️

プライバシーポリシーとサポートページはストア申請の必須項目なのに、後回しにしがちです。デプロイの仕組みを増やさずに済むこの方法なら腰も軽いので、申請準備のブロッカーになる前にサクッと済ませておくのがおすすめです。
