import Flutter
import Foundation

// STT モデル（NeMo）の実パスを Dart へ返すためのネイティブブリッジ。
//   iOS では Bundle.main から「アプリに同梱したファイルの実パス」が取れる。
//   Dart からは直接 Bundle.main を呼べないため、MethodChannel 経由で住所を返す。
enum SttModelChannel {
  // Dart 側と一致させるチャンネル名・メソッド名
  static let channelName = "jp.momeo/stt_models"
  static let getModelPathsMethod = "getModelPaths"

  // バンドルに同梱したファイル（名前と拡張子を分けて Bundle.main に問い合わせる）
  private static let nemoResource = "model.int8"
  private static let nemoExtension = "onnx"
  private static let tokensResource = "tokens"
  private static let tokensExtension = "txt"

  // 通話線（MethodChannel）を1本立て、問い合わせに応える
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case getModelPathsMethod:
        handleGetModelPaths(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // NeMo 本体と tokens の実パスをまとめて返す。
  // 見つからなければ FlutterError を返し、Dart 側で気づけるようにする。
  private static func handleGetModelPaths(result: FlutterResult) {
    guard let modelPath = Bundle.main.path(forResource: nemoResource, ofType: nemoExtension) else {
      result(missingFileError(nemoResource, nemoExtension))
      return
    }
    guard let tokensPath = Bundle.main.path(forResource: tokensResource, ofType: tokensExtension) else {
      result(missingFileError(tokensResource, tokensExtension))
      return
    }
    result([
      "model": modelPath,
      "tokens": tokensPath,
    ])
  }

  private static func missingFileError(_ name: String, _ ext: String) -> FlutterError {
    return FlutterError(
      code: "model_not_found",
      message: "バンドルに \(name).\(ext) が見つかりません（Xcode への登録漏れの可能性）",
      details: nil
    )
  }
}
