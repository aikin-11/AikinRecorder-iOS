@preconcurrency import AVFoundation
import Speech

// Buffers leave the real-time tap as copies; conversion and disk I/O run on one serial queue.
final class AudioCapture: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.aikin.recorder.capture", qos: .userInitiated)
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var inputFormat: AVAudioFormat?
    private let onLevel: @Sendable (Float) -> Void
    private let onPCM: (@Sendable (UnsafePointer<Float>, Int, Double) -> Void)?
    private let onFailure: @Sendable (String) -> Void
    private var failed = false

    init(url: URL, inputFormat: AVAudioFormat, analyzerFormat: AVAudioFormat?,
         continuation: AsyncStream<AnalyzerInput>.Continuation?,
         onLevel: @escaping @Sendable (Float) -> Void,
         onPCM: (@Sendable (UnsafePointer<Float>, Int, Double) -> Void)? = nil,
         onFailure: @escaping @Sendable (String) -> Void) throws {
        self.analyzerFormat = analyzerFormat
        self.continuation = continuation
        self.inputFormat = inputFormat
        self.onLevel = onLevel
        self.onPCM = onPCM
        self.onFailure = onFailure
        file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVEncoderBitRateKey: 128_000
        ], commonFormat: inputFormat.commonFormat, interleaved: inputFormat.isInterleaved)
        if let analyzerFormat {
            converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)
            guard converter != nil else { throw RecorderError.message("无法转换麦克风音频格式。") }
        }
    }

    func attachAnalyzer(format: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        queue.async { [self] in
            analyzerFormat = format
            self.continuation = continuation
            if let inputFormat { converter = AVAudioConverter(from: inputFormat, to: format) }
        }
    }

    func append(_ input: AVAudioPCMBuffer) {
        guard let copy = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: input.frameLength) else { return }
        copy.frameLength = input.frameLength
        let from = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input.audioBufferList))
        let to = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in 0..<from.count {
            guard let source = from[index].mData, let destination = to[index].mData else { continue }
            memcpy(destination, source, Int(from[index].mDataByteSize))
        }
        queue.async { [self] in
            guard !failed else { return }
            do {
                try file?.write(from: copy)
                if let samples = copy.floatChannelData?[0], copy.frameLength > 0 {
                    onPCM?(samples, Int(copy.frameLength), copy.format.sampleRate)
                }
                guard let format = analyzerFormat, let converter, let continuation else { return }
                let capacity = AVAudioFrameCount(ceil(Double(copy.frameLength) * format.sampleRate / copy.format.sampleRate)) + 64
                guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
                var supplied = false
                var error: NSError?
                let status = converter.convert(to: output, error: &error) { _, state in
                    if supplied { state.pointee = .noDataNow; return nil }
                    supplied = true
                    state.pointee = .haveData
                    return copy
                }
                if let error { throw error }
                if status != .error && output.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: output)) }
            } catch {
                failed = true
                onFailure(error.localizedDescription)
            }
        }
    }

    func close() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                file = nil
                self.continuation?.finish()
                continuation.resume()
            }
        }
    }
}
