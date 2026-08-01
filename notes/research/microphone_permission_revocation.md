# マイク権限を後から剥奪されたときの挙動に関する調査

## この文書について

- **目的**: アプリの利用中（特にバックグラウンド滞在中）にマイク権限を OFF にされた場合、復帰時に「設定を促す画面」へ戻れるのかを、実装・OS 挙動の両面から確認する。
- **調査日**: 2026-07-27
- **対象**: iOS（プライバシー設定変更時のプロセス終了）、Android（runtime permission の revoke）、`permission_handler` 12.0.2
- **検証環境**: iOS 18.4 シミュレータ（iPhone 16 Pro Max）、Android 17 / API 37 エミュレータ。いずれも debug ビルドをデバッガ非アタッチで起動して実測した
- **きっかけ**: 「背面に回す → 設定でマイクを OFF → アプリに戻る」で設定誘導画面が出ることを意図していたが、実際にはそうなっていないように見えた。意図して実装されているのか、されていないなら何をすべきかを整理したい。

---

## TL;DR（結論サマリ）

**ユーザーが詰むことはない。ただし「復帰した瞬間に設定を促す画面を出す」ことは、現行 OS では原理的に実現できない。**

- 設定でマイクを off にすると、**iOS も Android も OS がアプリを強制終了する**。復帰は「再開」ではなく「再起動」になる。
- 再起動後は起動フローが権限を判定するため、**設定を促す画面には到達する**（iOS は「設定を開く」、Android は「許可する」）。実測で確認済み。
- したがって「アプリが使えなくなったまま戻れない」という状態は発生しない。違いは体感だけで、モーダルではなく再起動を挟む。
- 実装済みの `didChangeAppLifecycleState` による再チェックは、**権限フロー画面を表示している間しか動かない**。フロー通過後の監視は存在しない。
- ただし現行 OS には「権限を失ったまま生き残って復帰する」経路が存在しないため、フロー通過後の監視を足しても**発火する場面がない**（§3-3・§2-5 の実測）。
- 監視が意味を持ち始めるのは、バックグラウンド録音を入れてアプリが長時間生き続けるようになってからである。

---

## 1. 現状の実装

### 1-1. 再チェックはどこにあるか

復帰時に権限を読み直すコードは `lib/pages/permissions/permission_flow_page.dart:69-77` にある。

```dart
if (state == AppLifecycleState.resumed) {
  _recheckCurrentPermission();
}
```

`WidgetsBindingObserver` を持っているのは `PermissionFlowPage` 自身であり、この画面が生きている間しか通知を受け取らない。

### 1-2. フロー通過後は監視が消える

`lib/main.dart:79` の `_permissionFinished` は一度 `true` になると `false` へ戻らない。`lib/main.dart:108-114` の分岐を抜けた時点で `PermissionFlowPage` はツリーから外れ、`dispose()` で observer も解除される。

| タイミング | 権限の再チェック |
|---|---|
| 権限フロー表示中（「設定を開く」から戻ってきた直後） | 動く |
| リスニング画面に入った後 | 動かない |

つまり、この再チェックは「設定アプリへ誘導した直後の1往復」だけを見るための実装であり（`notes/specs/permission_flow.md:23` の記述どおり）、**アプリ全体としての復帰時再チェックは未実装**である。

### 1-3. 権限を失った状態で録音を開始した場合

`lib/stt/stt_listening_pipeline.dart:108-112` が `StateError` を投げるが、`lib/providers/listening_providers.dart:158-161` の `catch` が `debugPrint` するだけで握り潰す。ユーザー向けのエラー表示は存在しない。

---

## 2. iOS の挙動

### 2-1. OS がアプリを強制終了する

iOS は設定アプリでプライバシー権限を変更した時点で、対象アプリを **SIGKILL する**。背面に滞在していても同じである。Apple の公式ドキュメントには記載がないが、Developer Forums に複数の報告があり、マイク・カメラで再現する。

権限を **ON に戻したとき**も同様に kill される点に注意する。

### 2-2. 実際に起きること（リリースビルド）

```text
背面へ
→ 設定でマイク OFF
→ iOS がアプリを SIGKILL
→ アプリに戻る = コールドスタート
→ Splash（2回目以降なので 'momeo' の短縮版）
→ 権限フロー: status = permanentlyDenied → settings 状態
→ 「設定からマイクの使用を許可してください / 設定を開く」
```

`permanentlyDenied` になる根拠は plugin 側の実装にある。`permission_handler_apple-9.4.8` の `AudioVideoPermissionStrategy.m:75-76` が `AVAuthorizationStatusDenied` を `PermissionStatusPermanentlyDenied` へマップし、`lib/pages/permissions/permission_controller.dart:52` がそれを `settings` へ変換する。

**意図した画面自体は表示される。** ただし体感は「復帰したら画面が出る」ではなく「アプリが一度落ち、再タップで splash から権限画面」になる。

### 2-3. 「出ていない」ように見える原因

1. **`flutter run`（デバッグ）で検証している** — デバッガがアタッチされているため、プロセスが死んでもアプリがフリーズして見える。開発時だけの現象（`notes/specs/permission_flow.md:62`）。
2. **見え方が意図と異なる** — 上記 2-2 のとおり、復帰ではなく再起動として現れる。

### 2-4. 副作用: 再チェックが機能しない

「設定を開く」で権限を ON にして戻る経路も iOS は kill するため、復帰ではなく再起動になる。`didChangeAppLifecycleState` は呼ばれず、**iOS ではこの再チェックが一度も働かない**。

### 2-5. 実行中のアプリは剥奪を観測できない（実測）

kill を回避しても、iOS のアプリは権限の剥奪を検知できない。

シミュレータの `TCC.db` を直接書き換えて `auth_value` を 0（拒否）にし、`tccd` を再起動したうえでアプリを背面から復帰させた。プロセスは同じ PID のまま生き残り、復帰時の再チェックも実行されたが、返ってきた結果は **`granted=true`** だった。`AVCaptureDevice` の認可状態がアプリのプロセス内にキャッシュされるためである。

| 手順 | 結果 |
|---|---|
| 背面化 | プロセス存続 |
| `TCC.db` を拒否に書き換え + `tccd` 再起動 | プロセス存続（同一 PID） |
| 復帰 | 再チェックは発火。ただし `granted=true` |

**iOS が設定変更時にアプリを kill するのは、これが理由である。** kill しない限り、新しい権限状態をアプリに反映させる手段がない。裏を返せば、iOS で「生きたまま剥奪を検知して画面を出す」ことは実装のしようがない。

---

## 3. Android の挙動

### 3-1. 通常の revoke ではプロセスが kill される

設定 → アプリ → 権限から revoke した場合、Android はアプリのプロセスを終了させる。公式ドキュメントにも次の記述がある。

> "As with any permission, if the user revokes your app's one-time permission, your app's process terminates."

復帰時はタスクが復元されて Activity が再生成され、Flutter は `main()` から始まる。したがって splash → 権限フローという iOS と同じ経路をたどる。

### 3-2. iOS と表示される画面が違う

Android の `.status` は `permanentlyDenied` を返さない。`permission_handler_android-13.0.1` の `PermissionManager.determinePermissionStatus` は GRANTED / DENIED / RESTRICTED / LIMITED しか返さず、`NEVER_ASK_AGAIN` は `PermissionUtils.determineDeniedVariant` 経由、つまり `request()` を呼んだときにしか現れない。

| プラットフォーム | 表示される状態 | 画面 |
|---|---|---|
| iOS | `settings` | 「設定からマイクの使用を許可してください / 設定を開く」 |
| Android | `request` | 「音声を認識するためにマイクを使います / 許可する」→ タップで OS ダイアログ |

Android のほうが操作が1段短い。ユーザーが設定から手動で revoke した場合は `shouldShowRequestPermissionRationale` がリセットされるため、`request()` で OS ダイアログが正しく再表示される。

### 3-3. kill されない抜け道は、現行版では見つからなかった（実測）

当初は「プロセスが生き残る revoke 経路があり、そこが穴になる」と想定したが、Android 17 / API 37 で実測したところ**いずれも kill された**。

| ケース | 実測結果 |
|---|---|
| 「今回のみ許可」の期限切れ | 背面化から約80秒で失効し、**プロセスも kill された**。復帰は再起動になり、`request` 画面（「許可する」）が出る |
| `pm reset-permissions`（設定アプリの「アプリの設定をリセット」相当） | **kill された** |
| 設定アプリからの通常の revoke | **kill された** |

「アプリの設定をリセットではプロセスが kill されない」という情報は CommonsWare の 2015 年（Android 6 時代）の記事に基づくもので、**現行版には当てはまらない**。

残る可能性は OEM の独自挙動（Xiaomi・OPPO など）だけだが、これは手元で再現できていない。

このケースが仮に起きた場合、アプリは生きたまま戻ってくるので、**画面は普通のリスニング画面のまま、録音だけが死んだ状態**になる。§1-3 のとおりエラー表示もない。

---

## 4. 併発する別問題（権限とは無関係だが同じ症状になる）

背面 → 復帰でパイプラインが復活しない可能性がある。

- `listeningProvider` は `autoDispose` だが、背面化では画面が unmount されないため dispose されない。
- `SttListeningPipeline` は止まったまま残り、復帰時に `start()` を呼び直す仕組みがどこにもない。

結果として「アプリは動いているのに聞いていない」という、3-3 と見分けのつかない状態になる。権限の検証をするときはこちらも同時に確認する必要がある。`notes/background_recording/overview.md` の調査と地続きの論点である。

---

## 5. 実装するなら（保険としての形）

前提として、**現行 OS では追加実装なしでも設定を促す画面には到達する**（再起動経由）。ここで足すのは、その経路が使えない場合に備えた保険である。

意図（復帰時に設定を促す画面へ戻る）を満たす最小の形は、**再チェックを `RootView` に上げる**ことである。

1. `RootView` を `WidgetsBindingObserver` にする
2. `resumed` で `Permission.microphone.status` を確認する
3. granted でなければ `_permissionFinished` を `false` に戻す

これだけで既存部品がそのまま再利用できる。

- `PermissionFlowPage` が再表示され、`_initFlow` が状態を判定して settings / request 画面を出す。**新しい画面もモーダルも作らなくてよい**
- `ListeningPage` がツリーから外れ、`listeningProvider` が autoDispose で破棄されるので、パイプラインも一緒に止まる
- `_splashFinished` は `true` のままなので splash は再生されない。意図どおり「復帰したら権限画面」の見え方になる

### 現行 OS では発火しない（実測）

この対応を入れたうえで実測した結果は次のとおり。

| 確認項目 | 結果 |
|---|---|
| 復帰時に再チェックが呼ばれるか | **呼ばれる**（同一 PID のまま復帰したログで確認） |
| 権限が生きているときの挙動 | **何も起きない**（画面そのまま。リグレッションなし） |
| 権限を失ったまま生き残って復帰する経路 | **見つからなかった**（§2-5・§3-3） |

つまり現時点では、この保険が実際に発動する場面はない。意味を持ち始めるのは、バックグラウンド録音（`UIBackgroundModes: audio` / フォアグラウンドサービス）を入れてアプリが長時間生き続けるようになってからである。特に Android は常駐通知付きのフォアグラウンドサービスでプロセスが維持されるため、そこが本番になる。

### 検証の前提

iOS の検証は**リリースビルドの実機**で行う。デバッグビルドではプロセス終了がフリーズとして現れ、判断できない。

---

## 6. 仕様書との差分

`notes/specs/permission_flow.md:57-64`「iOSで権限をoffにした時の挙動」の「追加実装は不要です」という結論は、**実測の結果 iOS・Android の両方で正しかった**。当初は「Android には kill されない revoke 経路があるので不足している」と考えたが、§3-3 のとおり現行版では再現しなかった。

ただし仕様書の記述は iOS の話に限定されているため、次の2点を追記すると読み手の理解が揃う。

- Android も設定からの revoke でプロセスが kill され、復帰は再起動になること（表示は `request` 側になる点も含む）
- 権限フロー通過後は権限の監視が存在しないこと。現行 OS では問題にならないが、バックグラウンド録音を入れる際は前提が変わること

---

## 7. 参考リンク

### Apple
- [Microphone permission change restarts running App — Apple Developer Forums](https://developer.apple.com/forums/thread/125647)
- [App crashes when changing privacy settings — Apple Developer Forums](https://developer.apple.com/forums/thread/64740)
- [EXC_CRASH (SIGKILL) — Apple Developer Documentation](https://developer.apple.com/documentation/xcode/sigkill)

### Android
- [Request runtime permissions](https://developer.android.com/training/permissions/requesting)
- [Permissions updates in Android 11](https://developer.android.com/about/versions/11/privacy/permissions)
- [SecurityExceptions, Runtime Permissions, and "Reset app preferences" — CommonsWare](https://commonsware.com/blog/2015/11/24/securityexceptions-runtime-permissions-reset-app-preferences.html) — 2015 年（Android 6 時代）の記事。§3-3 のとおり現行版では再現しない

### パッケージ
- [permission_handler (pub.dev)](https://pub.dev/packages/permission_handler)

---

## 8. 関連ドキュメント

- `notes/specs/permission_flow.md` — 権限フローの仕様
- `notes/background_recording/overview.md` — バックグラウンド録音の可否調査
- `notes/specs/listening_flow.md` — リスニングフローの仕様
