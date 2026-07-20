## 概要

個人でスマホアプリを作っています。

App Store に出す準備の最初の一歩として、Apple Developer サイトで **App ID(バンドルID)の登録**をやりました。5分で終わる住民登録みたいなもので、「このバンドルIDのアプリはうちのチームのものです」と Apple の台帳に載せるだけです。

## そもそも App ID ってなに？

- アプリを識別する ID。実体はバンドルID(例: `jp.example.yourapp`)
- App Store Connect でアプリを作るとき、この台帳に載っている ID しか選べない
- つまり **App Store に出すなら登録必須**

## 手順は4ステップ

[Apple Developer](https://developer.apple.com/account) → Certificates, Identifiers & Profiles → **Identifiers** から。

1. **＋ボタン** → 「App IDs」を選んで Continue
2. type は「**App**」を選んで Continue
3. 登録フォームに入力
   - **Description**: 管理用の名前。アプリ名でOK(記号は不可)
   - **Bundle ID**: 「**Explicit**」を選んで、Xcode プロジェクトの `PRODUCT_BUNDLE_IDENTIFIER` と同じ文字列を入力
   - **Capabilities**: 使うものだけチェック。何も使わないなら全部ノーチェックでOK(マイク・カメラなどの権限は Info.plist の世界なのでここには不要)
4. Continue → Register で完了

一覧に自分のバンドルIDの行が増えていれば成功です。これで App Store Connect でアプリを作れるようになります。
