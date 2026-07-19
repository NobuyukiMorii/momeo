# Cloudflare で独自ドメインのメールアドレスを無料で作る手順

`support@momeo.jp` のような momeo.jp ドメインのメールアドレスを、
**Cloudflare Email Routing + Gmail** の組み合わせで費用ゼロで用意する手順。
方法の比較検討は会話ベースだが、要点は本ファイルの「この方法を選ぶ理由」にまとめる。

## この方法を選ぶ理由


| 観点  | 内容                                                                |
| --- | ----------------------------------------------------------------- |
| 費用  | 完全無料(Cloudflare 無料プラン + 手持ちの Gmail)                               |
| 受信  | `support@momeo.jp` 宛のメールを Gmail に自動転送(アドレス数無制限)                   |
| 送信  | Gmail の「他のメールアドレスから送信(Send mail as)」で `support@momeo.jp` 名義で返信できる |
| 保守  | サーバー・コードの保守なし。設定は画面操作のみ                                           |
| 代償  | **ネームサーバーを Cloudflare へ移管する**(ドメイン自体はお名前.com のまま)                 |


- 有料の代替: さくらのメールボックス(月 88〜110 円。NS 移管不要・本物のメールボックス)
- AWS(SES)でも自作できるが、Lambda 転送の構築・保守が必要で、
得られる結果は同じなのに手間だけ大きい。WorkMail は 2027-03 でサービス終了のため選択肢外



## 仕組み

```
受信: 差出人 → momeo.jp の MX(Cloudflare) → Email Routing が Gmail へ転送
送信: Gmail(Send mail as) → smtp.gmail.com → 相手には support@momeo.jp 名義で届く
```

Email Routing は受信転送専用で、メールボックスは作られない。実体は Gmail に集約される。

## 全体の流れ

1. Cloudflare にドメインを追加し、DNS レコードを引き継ぐ
2. お名前.com でネームサーバーを Cloudflare に変更する
3. Email Routing を有効化し、`support@momeo.jp` → Gmail の転送を作る
4. Gmail の Send mail as で `support@momeo.jp` 名義の送信を設定する
5. サイト([docs/support.html](../../../docs/support.html) 等)の連絡先を差し替える

---



## 1. Cloudflare にドメインを追加

1. Cloudflare のアカウントを作成する(無料プラン(Free)でよい)
2. ダッシュボードで「サイトを追加」→ `momeo.jp` を入力 → Free プランを選択
3. 既存の DNS レコードが自動スキャンで取り込まれるので、内容を確認する。
  **GitHub Pages 用のレコードがない場合はここで追加しておく**
   ([github_pages_setup.md](../site/github_pages_setup.md) の DNS 設定と同内容):

  | タイプ | 名前       | 値               | プロキシ               |
  | --- | -------- | --------------- | ------------------ |
  | A   | momeo.jp | 185.199.108.153 | **DNS only(グレー雲)** |
  | A   | momeo.jp | 185.199.109.153 | DNS only           |
  | A   | momeo.jp | 185.199.110.153 | DNS only           |
  | A   | momeo.jp | 185.199.111.153 | DNS only           |
  | CNAME | www    | nobuyukimorii.github.io | DNS only    |

  - パーキング用の A レコード(150.95.255.38)が取り込まれていたら削除する
  - 自動スキャンは実在しないレコードも拾ってくることがある。
  `_dmarc` / `mail` / `www` / `test` などの **NS レコード(値が dns1/dns2.onamae.com)や
  パーキング由来の TXT(**`v=spf1 -all`**)が並んでいたら、すべて削除**してよい。
  残すのは GitHub Pages 用の上記 5 レコード(A 4 つ + www の CNAME)だけ
  - **プロキシ(オレンジ雲)は使わない**。GitHub Pages の前に Cloudflare の CDN を
  重ねると証明書発行やリダイレクトのトラブルの元になるため、全レコード DNS only にする



## 2. ネームサーバーの変更(お名前.com)

1. サイト追加の完了画面に、割り当てられた Cloudflare のネームサーバーが 2 つ表示される
  (例: `xxx.ns.cloudflare.com` / `yyy.ns.cloudflare.com`)
2. お名前.com の「ネームサーバーの設定」で、`dns1/dns2.onamae.com` を
  この 2 つに変更する
3. 反映は通常数時間、最大 72 時間。Cloudflare のダッシュボードが
  「アクティブ」になれば完了

以後、DNS レコードの追加・変更はすべて Cloudflare 側で行う
(お名前.com の DNS レコード設定画面は使わなくなる)。

## 3. Email Routing の設定

1. Cloudflare ダッシュボード → momeo.jp → **メール(Email Routing)** を開く
2. 転送先アドレス(手持ちの Gmail)を登録する → 確認メールが届くので承認する
3. カスタムアドレスを作成する:
  - `support@momeo.jp` → 転送先: 登録した Gmail
4. 有効化の途中で MX レコードと SPF(TXT)レコードの追加を求められるので、
  「自動で追加」に任せる
5. 別のメールアドレスから `support@momeo.jp` 宛に送り、Gmail に届くことを確認する

アドレスは何個でも無料で追加できる(例: `info@momeo.jp`)。
個別に作らず全部受けたい場合は「キャッチオール」も設定できるが、
スパムも全部届くようになるため、必要なアドレスだけ作るほうがよい。

## 4. Gmail からの送信設定(Send mail as)

`support@momeo.jp` 名義で返信できるようにする。

1. Google アカウントで 2 段階認証を有効にし、**アプリパスワード**を発行する
  (Google アカウント管理 → セキュリティ → アプリパスワード)
2. Gmail の設定 → **アカウントとインポート** → 「他のメールアドレスを追加」
3. 次の内容で登録する:

  | 項目         | 値                               |
  | ---------- | ------------------------------- |
  | メールアドレス    | `support@momeo.jp`              |
  | エイリアスとして扱う | チェックする                          |
  | SMTP サーバー  | `smtp.gmail.com`(ポート 587 / TLS) |
  | ユーザー名      | 自分の Gmail アドレス                  |
  | パスワード      | 1. で発行したアプリパスワード                |

4. `support@momeo.jp` 宛に確認コードが送られる。Email Routing 経由で
  Gmail に届くので、コードを入力して完了
5. 迷惑メール判定を減らすため、Cloudflare の DNS で SPF レコード(TXT)に
  Gmail の送信サーバーを追記する:
6. 返信時に差出人として `support@momeo.jp` を選べるようになる。
  「デフォルトの返信モード」を「受信したアドレスから返信する」にしておくと、
   support 宛に来たメールへは自動で support 名義になる



## 5. サイト側の連絡先の差し替え

- [docs/support.html](../../../docs/support.html): 連絡先メールアドレスを `support@momeo.jp` に変更する
- ストア申請フォームのサポート用メールアドレスにも同じアドレスを使う

---



## 注意事項

- **Email Routing は受信転送専用**。大量送信(メルマガ等)の用途には使えない。
サポート窓口の受信 + 個別返信という用途なら十分
- **MX レコードはドメインにつき 1 系統**。将来 AWS SES の「受信」を momeo.jp で
使いたくなった場合は Email Routing と同居できない(サブドメインの MX で回避可能)。
SES の「送信」や他の AWS サービスとの併用には影響しない
- NS 移管後、GitHub Pages の DNS check が一時的に外れることがある。
レコード内容が同じなら数時間で回復する
- Gmail SMTP 経由の送信は DKIM が momeo.jp ではなく gmail.com 署名になるため、
厳格な受信サーバーでは「via gmail.com」表示や迷惑メール判定の可能性が残る。
気になる場合は有料のメールボックス(さくら等)への移行を検討する

