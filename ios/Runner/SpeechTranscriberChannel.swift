import AVFoundation
import Flutter
import Foundation
import Speech

// OS 内蔵の文字起こし（SpeechTranscriber）を Dart から使うためのネイティブブリッジ。
//   VAD で区切った1発話ぶんの音（16kHz・Float32）を受け取り、テキストを返す。
//   言語は、設定の「優先する言語」のうち対応している最初のものに固定する（自動判定はしない）。
//   prepare の返事（state）は ready・downloading・unsupported の3つで、Android 側と同じ。
enum SpeechTranscriberChannel {
  // Dart 側と一致させるチャンネル名・メソッド名
  static let channelName = "jp.momeo/os_transcriber"
  static let prepareMethod = "prepare"
  static let transcribeMethod = "transcribe"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case prepareMethod:
        handlePrepare(result: result)
      case transcribeMethod:
        handleTranscribe(arguments: call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // ---------------------------------
  // 使えるかの確認とモデルの用意
  // ---------------------------------
  private static func handlePrepare(result: @escaping FlutterResult) {
    Task {
      let reply = await SpeechTranscriberEngine.shared.prepare()
      await MainActor.run { result(reply) }
    }
  }

  // ---------------------------------
  // 1発話ぶんの文字化
  // ---------------------------------
  private static func handleTranscribe(arguments: Any?, result: @escaping FlutterResult) {
    // Dart の Float32List は FlutterStandardTypedData として届く
    guard let typedData = arguments as? FlutterStandardTypedData else {
      result(FlutterError(code: "bad_arguments", message: "音声サンプル（Float32List）が届いていません", details: nil))
      return
    }
    let samples: [Float] = typedData.data.withUnsafeBytes { rawBuffer in
      Array(rawBuffer.bindMemory(to: Float.self))
    }

    Task {
      do {
        let text = try await SpeechTranscriberEngine.shared.transcribe(samples: samples)
        await MainActor.run { result(text) }
      } catch {
        await MainActor.run {
          result(FlutterError(code: "transcribe_failed", message: "\(error)", details: nil))
        }
      }
    }
  }
}

// ============================================================
// SpeechTranscriberEngine — SpeechAnalyzer で1発話ずつ文字化する
//
//   発話ごとに SpeechAnalyzer を作り、音を流し終えたら確定させて結果をまとめる。
//   モデル本体は OS が持っていて、アプリ側で読み込み直すものは無い。
// ============================================================
actor SpeechTranscriberEngine {
  static let shared = SpeechTranscriberEngine()

  private static let inputSampleRate: Double = 16000 // Dart から届く音のサンプリングレート

  // prepare が済むと埋まる
  private var locale: Locale?
  private var analyzerFormat: AVAudioFormat?

  // 進行中の言語のモデルのダウンロード（終わると nil に戻る）
  private var downloadTask: Task<Void, Never>?

  // ---------------------------------
  // 端末・言語の対応確認と、モデルのダウンロードの開始
  // ---------------------------------
  func prepare() async -> [String: Any] {
    guard SpeechTranscriber.isAvailable else {
      return ["state": "unsupported", "detail": "この端末では SpeechTranscriber が使えません"]
    }
    guard let supportedLocale = await findSupportedPreferredLocale() else {
      return [
        "state": "unsupported",
        "detail": "優先する言語（\(Locale.preferredLanguages.joined(separator: ", "))）のどれにも対応していません",
      ]
    }

    // ダウンロードの途中なら、始め直さずに終わるのを待ってもらう
    if downloadTask != nil {
      return ["state": "downloading", "detail": "\(supportedLocale.identifier) のモデルをダウンロード中です"]
    }

    let transcriber = makeTranscriber(locale: supportedLocale)
    do {
      // 端末にモデルが無ければ、ダウンロードを始めて、終わるのを待たずに返す
      if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        startDownload(request)
        return ["state": "downloading", "detail": "\(supportedLocale.identifier) のモデルのダウンロードを始めました"]
      }
    } catch {
      // 通信の途切れなど一時的な失敗もあるので、使えないとは決めず、次の prepare でやり直す
      return ["state": "downloading", "detail": "モデルを用意できませんでした: \(error)"]
    }

    locale = supportedLocale
    analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
    return [
      "state": "ready",
      "detail": "locale: \(supportedLocale.identifier) / format: \(analyzerFormat?.description ?? "-")",
    ]
  }

  // ダウンロードを裏で進める。失敗しても、次の prepare で始め直す
  private func startDownload(_ request: AssetInstallationRequest) {
    downloadTask = Task {
      do {
        try await request.downloadAndInstall()
      } catch {
        NSLog("[SpeechTranscriber] モデルのダウンロードに失敗しました: %@", "\(error)")
      }
      self.finishDownload()
    }
  }

  private func finishDownload() {
    downloadTask = nil
  }

  // ---------------------------------
  // 1発話ぶんの音を流して、確定したテキストを返す
  // ---------------------------------
  func transcribe(samples: [Float]) async throws -> String {
    guard let locale else {
      throw SpeechTranscriberError("prepare が済んでいません")
    }

    let transcriber = makeTranscriber(locale: locale)
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let buffer = try makeAnalyzerBuffer(samples: samples)

    // 結果の受け取りを先に始めておく（確定した区間の文字をつなげる）
    async let transcript = transcriber.results.reduce(into: "") { text, result in
      text += String(result.text.characters)
    }

    // 1発話ぶんの音だけを流して、入力を閉じる
    let (inputSequence, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
    inputContinuation.yield(AnalyzerInput(buffer: buffer))
    inputContinuation.finish()

    if let lastSampleTime = try await analyzer.analyzeSequence(inputSequence) {
      try await analyzer.finalizeAndFinish(through: lastSampleTime)
    } else {
      await analyzer.cancelAndFinishNow()
    }
    return try await transcript
  }

  // 設定の「優先する言語」を上から順に見て、SpeechTranscriber が対応している最初の言語を返す
  private func findSupportedPreferredLocale() async -> Locale? {
    for languageIdentifier in Locale.preferredLanguages {
      let preferredLocale = Locale(identifier: languageIdentifier)
      if let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: preferredLocale) {
        return supportedLocale
      }
    }
    return nil
  }

  private func makeTranscriber(locale: Locale) -> SpeechTranscriber {
    // 途中経過は使わず、確定した結果だけを受け取る
    return SpeechTranscriber(locale: locale, preset: .transcription)
  }

  // ---------------------------------
  // 16kHz・Float32 の音を、SpeechAnalyzer が受け付ける形式へ
  // ---------------------------------
  private func makeAnalyzerBuffer(samples: [Float]) throws -> AVAudioPCMBuffer {
    guard
      let sourceFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Self.inputSampleRate,
        channels: 1,
        interleaved: false
      ),
      let sourceBuffer = AVAudioPCMBuffer(
        pcmFormat: sourceFormat,
        frameCapacity: AVAudioFrameCount(samples.count)
      )
    else {
      throw SpeechTranscriberError("音声バッファを作れませんでした")
    }

    sourceBuffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { samplePointer in
      sourceBuffer.floatChannelData![0].update(from: samplePointer.baseAddress!, count: samples.count)
    }

    guard let targetFormat = analyzerFormat, targetFormat != sourceFormat else {
      return sourceBuffer
    }
    return try convert(sourceBuffer, to: targetFormat)
  }

  private func convert(_ sourceBuffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
    guard let converter = AVAudioConverter(from: sourceBuffer.format, to: targetFormat) else {
      throw SpeechTranscriberError("音声形式の変換器を作れませんでした（→ \(targetFormat)）")
    }

    let rateRatio = targetFormat.sampleRate / sourceBuffer.format.sampleRate
    let outputCapacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * rateRatio) + 1024
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
      throw SpeechTranscriberError("変換先の音声バッファを作れませんでした")
    }

    // 入力は1回だけ渡し、2回目以降は「もう無い」と答える
    var hasProvidedInput = false
    var conversionError: NSError?
    let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
      if hasProvidedInput {
        inputStatus.pointee = .endOfStream
        return nil
      }
      hasProvidedInput = true
      inputStatus.pointee = .haveData
      return sourceBuffer
    }

    if status == .error {
      throw SpeechTranscriberError("音声形式を変換できませんでした: \(String(describing: conversionError))")
    }
    return outputBuffer
  }
}

struct SpeechTranscriberError: LocalizedError {
  init(_ message: String) { self.message = message }
  let message: String
  var errorDescription: String? { message }
}
