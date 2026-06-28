// ============================================================
// NeMo（音声認識モデル・約625MB）を fast-follow で配るための「入れ物」
//
//   - これは :app とは別の小さな Android モジュール（アセットパック専用）。
//   - 中身（model.int8.onnx / tokens.txt）は src/main/assets/models/ に置く。
//     巨大なので Git には入れない（.gitignore）。bundletool 検証や本番ビルドの
//     直前にだけ配置する想定で、日常の `flutter run` では空のまま回す
//     （空のときは、端末に手置きしたモデルを代わりに使う）。
//   - delivery = fast-follow … インストール直後に Play が自動DLする配り方。
//     本体インストールには含めないので初回インストールは軽い。
//
//   ※ パック名「nemo_models」は Dart 側（ダウンロード操作・モデルのパス解決）から
//     この名前で参照する。変更するときは参照側も必ず揃えること。
// ============================================================

plugins {
    id("com.android.asset-pack")
}

assetPack {
    packName.set("nemo_models")
    dynamicDelivery {
        deliveryType.set("fast-follow")
    }
}
