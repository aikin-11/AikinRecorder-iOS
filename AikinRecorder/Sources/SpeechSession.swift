@preconcurrency import AVFoundation
import Speech

@MainActor
final class SpeechSession {
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var lines: [TranscriptLine] = []
    private var resultError: Error?
    var clock: (() -> TimeInterval)?
    var onLines: (([TranscriptLine]) -> Void)?
    var onStatus: ((String) -> Void)?

    private func prepare(localeID: String) async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else { throw RecorderError.message("当前设备不支持 Apple 本地转写模型。") }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else {
            throw RecorderError.message("Apple 本地转写暂不支持所选语言。")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        onStatus?("正在准备本地语言模型…")
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            onStatus?("首次使用需下载 Apple 语言模型，请保持联网…")
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()
        lines = []
        resultError = nil
        analyzer = SpeechAnalyzer(modules: [transcriber])
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    self.apply(text: text, provisional: !result.isFinal)
                    self.onLines?(self.lines)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.resultError = error
                self?.continuation?.finish()
                self?.onStatus?("转写遇到问题：\(error.localizedDescription)")
            }
        }
        return transcriber
    }

    func startLive(localeID: String) async throws -> (AVAudioFormat, AsyncStream<AnalyzerInput>.Continuation) {
        let transcriber = try await prepare(localeID: localeID)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]), let analyzer else {
            throw RecorderError.message("无法准备语音识别的音频格式。")
        }
        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
        continuation = builder
        try await analyzer.start(inputSequence: stream)
        onStatus?("本地实时转写")
        return (format, builder)
    }

    func finishLive() async {
        continuation?.finish()
        continuation = nil
        do { try await analyzer?.finalizeAndFinishThroughEndOfInput() }
        catch { onStatus?("录音已保存；转写结束时出现错误：\(error.localizedDescription)") }
        await resultsTask?.value
        analyzer = nil
        resultsTask = nil
    }

    func transcribeFile(_ url: URL, localeID: String) async throws {
        _ = try await prepare(localeID: localeID)
        guard let analyzer else { return }
        let file = try AVAudioFile(forReading: url)
        onStatus?("正在本地转写…")
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        await resultsTask?.value
        if let resultError { throw resultError }
        self.analyzer = nil
        resultsTask = nil
        onStatus?("转写完成")
    }

    private func apply(text: String, provisional: Bool) {
        if let index = lines.indices.last, lines[index].provisional {
            if provisional {
                lines[index].text = text
                return
            }
            lines.remove(at: index)
        }
        lines.append(TranscriptLine(time: clock?() ?? 0, text: text, provisional: provisional))
    }

    func cancel() async {
        continuation?.finish()
        continuation = nil
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
    }
}
