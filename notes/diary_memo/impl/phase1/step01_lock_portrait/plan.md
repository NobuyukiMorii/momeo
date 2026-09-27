# Step 1 縦画面に固定する

## 目的

端末を横にしても、画面を回転させない。

## やること


| OS      | 変更                        |
| ------- | ------------------------- |
| iOS     | 対応する向きを「縦」だけにする（横向き2つを外す） |
| Android | 画面の向きを「縦」に固定する            |


## 参照する `spike/diary-memo` のコード


| ファイル                                       | 場所                                                            |
| ------------------------------------------ | ------------------------------------------------------------- |
| `ios/Runner/Info.plist`                    | `UISupportedInterfaceOrientations`（71〜74行目）                   |
| `android/app/src/main/AndroidManifest.xml` | `MainActivity` の `android:screenOrientation="portrait"`（14行目） |


