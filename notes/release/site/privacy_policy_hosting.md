# プライバシーポリシーページのホスティング方法

momeo のストア公開([store_release_plan.md](../store_release_plan.md) Phase 0)に必要な
プライバシーポリシーページを momeo.jp で公開するための方法を比較検討する。
あわせて App Store で必須のサポートページも同じ場所に置く前提とする。

## 前提と現状

- ドメイン **momeo.jp は取得済み**(お名前.com)。DNS もお名前.com(`dns1/dns2.onamae.com`)
- 現在はお名前.com のパーキングページが表示されている状態。**HTTPS は未設定**
- 両ストアともプライバシーポリシーは **HTTPS の公開 URL** で提出する必要がある
- 掲載するのは静的なページ 2〜3 枚(プライバシーポリシー / サポート)。
  サーバーサイド処理・DB・更新頻度の高いコンテンツは不要

つまり要件は「momeo.jp で HTTPS の静的ページを数枚、無料〜低コストで公開する」に尽きる。

## 結論(先に)

**GitHub Pages + カスタムドメイン(momeo.jp)を推奨する。**

- 完全無料。HTTPS 証明書(Let's Encrypt)も自動で取得・更新される
- DNS はお名前.com のまま、**A レコードを 4 つ足すだけ**でよい(ネームサーバー移管が不要)
- ページは Git リポジトリで管理でき、push すれば反映される。普段の開発フローと同じ
- 静的ページ数枚という要件に対して、構築・運用の手間が最小

ネームサーバーを移管してもよいなら Cloudflare も同等以上に良い(後述)。

---

## 選択肢の比較

| 方法 | 費用 | momeo.jp(apex)で公開 | DNS 移管 | 構築の手間 | 備考 |
|---|---|---|---|---|---|
| **GitHub Pages** | 無料 | ○(A レコード) | 不要 | 小 | 推奨。HTTPS 自動 |
| Cloudflare(Workers Static Assets / Pages) | 無料 | ○ | **必要**(NS を Cloudflare へ) | 小 | 性能・拡張性は最良 |
| AWS(S3 + CloudFront + ACM) | 月 $1 前後 | ○(要 Route 53 移管) | 実質必要 | 中 | egg_shell の Terraform 資産を流用可 |
| Netlify | 無料 | ○(A/ALIAS) | 不要 | 小 | 無料枠は帯域 100GB/月 |
| Vercel | 無料(Hobby) | ○ | 不要 | 小 | Hobby プランは商用利用不可の規約に注意 |
| Firebase Hosting | 無料枠内 | ○ | 不要 | 小 | 無料枠: 転送 360MB/日 |
| お名前.com レンタルサーバー | 月数百円〜 | ○ | 不要 | 小 | 有料。静的数枚には過剰 |
| ポリシー生成サービスにホストさせる | 無料〜有料 | ×(先方ドメイン) | — | 最小 | momeo.jp 掲載の方針に合わない |

### 1. GitHub Pages(推奨)

- リポジトリに HTML(または Markdown + Jekyll)を置くだけで公開できる
- カスタムドメインは apex(momeo.jp)に対応。お名前.com 側で A レコードを
  GitHub Pages の固定 IP 4 つに向ければよい
- HTTPS は GitHub が Let's Encrypt 証明書を自動発行・自動更新(「Enforce HTTPS」を有効にする)
- 制限: サイト 1GB・帯域 100GB/月(ソフトリミット)。ポリシーページには全く問題ない
- 注意: public リポジトリなら無料。private リポジトリで Pages を使うには有料プランが必要

### 2. Cloudflare(Workers Static Assets / Pages)

- 無料枠で静的配信は実質無制限。CDN 配信で速い
- 2026 年時点で Cloudflare は新規プロジェクトを Workers(Static Assets)側に誘導しており、
  Pages は現状維持のサポート。どちらでも要件は満たせる
- **カスタムドメインはネームサーバーを Cloudflare に移す必要がある**のが唯一のハードル
  (ドメイン管理自体はお名前.com のままでよい。NS レコードの変更のみ)
- 将来 momeo.jp でランディングページやフォームなどを拡張する予定があるなら、
  最初から Cloudflare に寄せておく価値がある

### 3. AWS(S3 + CloudFront + ACM + Route 53)

- 構成: S3 に静的ファイル → CloudFront で配信 → ACM の無料証明書で HTTPS
- egg_shell に同構成の Terraform があるため、パターンの流用はしやすい
- ただし apex ドメインを CloudFront に向けるには **ALIAS レコードが必要**で、
  お名前.com の DNS は apex の ALIAS に対応していない。実質 Route 53 への DNS 移管が要る
  (ホストゾーン $0.50/月 + CloudFront/S3 で合計 月 $1 前後)
- インフラ管理の対象が増えるわりに得るものが少なく、ポリシーページ数枚には過剰

### 4. Netlify / Vercel / Firebase Hosting

- いずれも無料枠で静的サイト + カスタムドメイン + 自動 HTTPS に対応し、手間も小さい
- GitHub Pages と比べた決定的な利点がこの用途では無い
- Vercel の Hobby(無料)プランは規約上、商用利用が禁止。無料アプリのポリシーページが
  商用に当たるかはグレーなので、あえて選ぶ理由はない
- Firebase Hosting は無料枠(転送 360MB/日)で足りるが、Google アカウント・
  プロジェクト管理が 1 つ増える

### 5. ポリシー生成サービス(参考)

iubenda / Termly / TermsFeed / App Privacy Policy Generator など、
ポリシー文面の生成と先方ドメインでのホスティングをセットで提供するサービスがある。

- URL が先方ドメイン(例: `iubenda.com/privacy-policy/...`)になるため、
  「momeo.jp に掲載」という決定事項([store_release_plan.md](../store_release_plan.md))に合わない
- momeo は「データを一切外部送信しない」構成で、ポリシー文面自体が短く自力で書ける。
  生成サービスに頼る動機も薄い
- 文面の網羅性チェック(項目の抜け漏れ確認)の参考として眺める程度の用途に留める

---

## 採用方針

GitHub Pages を採用する。公開用の別リポジトリや専用ブランチは作らず、
**既存リポジトリ(NobuyukiMorii/momeo)の main ブランチの `/docs` フォルダ**で
サイトを管理する(開発ドキュメントは `notes/` に分離済みのため `docs/` を公開専用にできる)。

- リポジトリは public のため追加費用なし
- ブランチ分離も Actions ワークフローも不要で、普段どおり main に push するだけ
- `docs/` は静的サイト 1 個分をまるごと持てるので、
  プライバシーポリシー以外(ランディングページ・サポートページ等)も同じ枠で増やせる

具体的な公開手順は [github_pages_setup.md](github_pages_setup.md) を参照。
