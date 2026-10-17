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
    var onProgress: ((Double) -> Void)?
    private var filePaused = false
    var submitted: TimeInterval = 0

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
                    let spokenAt = result.range.start.seconds
                    self.apply(text: text, time: spokenAt.isFinite ? spokenAt : (self.clock?() ?? 0), provisional: !result.isFinal)
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

    func setFilePaused(_ paused: Bool) { filePaused = paused }

    func transcribeFile(_ url: URL, localeID: String, from start: TimeInterval) async throws {
        let transcriber = try await prepare(localeID: localeID)
        guard let analyzer else { return }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw RecorderError.message("无法准备语音识别的音频格式。")
        }
        let file = try AVAudioFile(forReading: url)
        let total = Double(file.length) / file.fileFormat.sampleRate
        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
        continuation = builder
        try await analyzer.start(inputSequence: stream)
        onStatus?(start > 0.5 ? "继续转写…" : "正在本地转写…")
        let reader = try AVAudioFile(forReading: url)
        let chunk = AVAudioFrameCount(max(1024, reader.processingFormat.sampleRate / 5))
        reader.framePosition = AVAudioFramePosition(max(0, start) * reader.processingFormat.sampleRate)
        var converter: AVAudioConverter? = reader.processingFormat == format ? nil : AVAudioConverter(from: reader.processingFormat, to: format)
        while reader.framePosition < reader.length {
            try Task.checkCancellation()
            while filePaused {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(120))
            }
            guard let input = AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: chunk) else { break }
            try reader.read(into: input)
            if input.frameLength == 0 { break }
            submitted = Double(reader.framePosition) / reader.processingFormat.sampleRate
            onProgress?(total > 0 ? min(1, submitted / total) : 0)
            if let converter {
                let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * format.sampleRate / reader.processingFormat.sampleRate)) + 32
                guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { continue }
                var supplied = false
                var error: NSError?
                converter.convert(to: output, error: &error) { _, state in
                    if supplied { state.pointee = .noDataNow; return nil }
                    supplied = true
                    state.pointee = .haveData
                    return input
                }
                if output.frameLength > 0 { builder.yield(AnalyzerInput(buffer: output)) }
            } else {
                builder.yield(AnalyzerInput(buffer: input))
            }
            try await Task.sleep(for: .milliseconds(30))
        }
        builder.finish()
        continuation = nil
        do { try await analyzer.finalizeAndFinishThroughEndOfInput() }
        catch { onStatus?("转写结束时出现错误：\(error.localizedDescription)") }
        await resultsTask?.value
        if let resultError { throw resultError }
        self.analyzer = nil
        resultsTask = nil
        submitted = total
        onProgress?(1)
        onStatus?("转写完成")
    }

    private func apply(text: String, time: TimeInterval, provisional: Bool) {
        let stamp = time.isFinite && time >= 0 ? time : (clock?() ?? 0)
        if let index = lines.indices.last, lines[index].provisional {
            lines[index].text = text
            if lines[index].time <= 0 { lines[index].time = stamp }
            lines[index].provisional = provisional
            return
        }
        lines.append(TranscriptLine(time: stamp, text: text, provisional: provisional))
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
