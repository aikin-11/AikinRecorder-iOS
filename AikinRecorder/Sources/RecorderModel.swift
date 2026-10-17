@preconcurrency import AVFoundation
import Observation
import UIKit
import Speech

@MainActor @Observable
final class RecorderModel {
    enum State { case idle, preparing, recording, paused, saving, saved }
    private(set) var state: State = .idle
    var title = Recording.meetingTitle()
    var lines: [TranscriptLine] = []
    var status = "点击下方按钮开始录音"
    var errorMessage: String?
    var elapsed: TimeInterval = 0
    var levels: [Float] = Array(repeating: 0, count: 48)
    var localeID = "zh-CN"
    var liveTranscription = true
    var transcriptionEngine = "local"
    private let engine = AVAudioEngine()
    private var capture: AudioCapture?
    private var speech: SpeechSession?
    private var bailian: BailianRealtime?
    private let downsampler = PCMDownsampler()
    private var item: Recording?
    private var timer: Task<Void, Never>?
    private var startTime: Date?
    private var elapsedBeforePause: TimeInterval = 0
    private var interruptionObserver: NSObjectProtocol?
    private var hasTap = false
    private var lastActivityUpdate: Date?
    private let levelMeter = LevelMeter()
    private var activityLevels: [Double] = [0.15, 0.15, 0.15, 0.15, 0.15]
    var marks: [RecordingMark] = []
    private var markObserver: NSObjectProtocol?

    var transcript: String {
        lines.filter { !$0.provisional }.map(\.text).joined(separator: "\n")
    }

    var hasUnsavedRecording: Bool { state == .recording || state == .paused || state == .saving }

    func start(in store: LibraryStore) async {
        guard state == .idle else { return }
        state = .preparing
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else {
            state = .idle
            errorMessage = "请在 iPhone 设置中允许 Aikin录音使用麦克风。"
            return
        }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true)
            var format: AVAudioFormat?
            var builder: AsyncStream<AnalyzerInput>.Continuation?
            if liveTranscription && transcriptionEngine == "bailian" {
                let service = BailianRealtime()
                service.onText = { [weak self] text, finished in
                    Task { @MainActor in self?.applyBailian(text, finished: finished) }
                }
                service.onStatus = { [weak self] message in
                    Task { @MainActor in self?.status = message }
                }
                try await service.start()
                bailian = service
            } else if liveTranscription {
                let service = SpeechSession()
                service.clock = { [weak self] in self?.elapsed ?? 0 }
                service.onLines = { [weak self] lines in
                    Task { @MainActor in
                        self?.lines = lines
                        self?.pushActivity(force: true)
                    }
                }
                service.onStatus = { [weak self] message in
                    Task { @MainActor in self?.status = message }
                }
                do {
                    let prepared = try await service.startLive(localeID: localeID)
                    format = prepared.0
                    builder = prepared.1
                    speech = service
                } catch {
                    await service.cancel()
                    status = "实时转写暂不可用；录音继续，保存后可重试转写。"
                    errorMessage = error.localizedDescription
                }
            } else { status = "仅录音" }
            try Task.checkCancellation()
            var draft = try store.createDraft()
            draft.title = Recording.cleanTitle(title)
            try store.update(draft)
            item = draft
            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw RecorderError.message("麦克风当前不可用，请检查音频设备。") }
            let pipeline = try AudioCapture(url: store.audioURL(for: draft), inputFormat: inputFormat,
                analyzerFormat: format, continuation: builder,
                onLevel: { [levelMeter] value in levelMeter.set(value) },
                onPCM: bailian == nil ? nil : { [downsampler, weak bailian] samples, count, rate in
                    let pcm = downsampler.convert(samples, count: count, sampleRate: rate)
                    bailian?.appendPCM(pcm)
                },
                onFailure: { [weak self, weak store] message in Task { @MainActor in
                    self?.errorMessage = "音频写入失败：\(message)"
                    if let self, let store { await self.finish(in: store) }
                } })
            capture = pipeline
            input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in pipeline.append(buffer) }
            hasTap = true
            engine.prepare()
            try engine.start()
            state = .recording
            startTime = .now
            UIApplication.shared.isIdleTimerDisabled = true
            RecordingActivity.start(title: Recording.cleanTitle(title), elapsed: 0)
            markObserver = NotificationCenter.default.addObserver(forName: .aikinRecordingMark, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.addMark() }
            }
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(33))
                    guard let self else { return }
                    if self.state == .recording, let start = self.startTime { self.elapsed = self.elapsedBeforePause + Date().timeIntervalSince(start) }
                    self.sampleLevel()
                    self.pushActivity(force: false)
                }
            }
            interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                object: nil, queue: .main) { [weak self, weak store] notification in
                    guard let kind = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                          kind == AVAudioSession.InterruptionType.began.rawValue else { return }
                    Task { @MainActor in
                        guard let self, let store, self.hasUnsavedRecording else { return }
                        self.status = "音频被系统中断，正在保存录音。"
                        await self.finish(in: store)
                    }
                }
        } catch {
            engine.stop()
            if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
            await capture?.close()
            capture = nil
            await speech?.cancel()
            speech = nil
            await bailian?.finish()
            bailian = nil
            if let item { try? store.remove(item) }
            item = nil
            state = .idle
            errorMessage = error.localizedDescription
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }

    func togglePause() {
        do {
            if state == .recording {
                engine.pause()
                elapsedBeforePause = elapsed
                startTime = nil
                state = .paused
                pushActivity(force: true)
            } else if state == .paused {
                try engine.start()
                startTime = .now
                state = .recording
                pushActivity(force: true)
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func finish(in store: LibraryStore) async {
        guard state == .recording || state == .paused else { return }
        state = .saving
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SaveRecording")
        defer { if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) } }
        timer?.cancel()
        timer = nil
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        await capture?.close()
        capture = nil
        await speech?.finishLive()
        speech = nil
        await bailian?.finish()
        bailian = nil
        if let observer = interruptionObserver { NotificationCenter.default.removeObserver(observer); interruptionObserver = nil }
        if let observer = markObserver { NotificationCenter.default.removeObserver(observer); markObserver = nil }
        if var item {
            item.title = Recording.cleanTitle(title)
            item.transcript = transcript
            item.lines = lines.filter { !$0.provisional }.map { TranscriptCue(id: $0.id, time: $0.time, text: $0.text) }
            item.marks = marks
            let asset = AVURLAsset(url: store.audioURL(for: item))
            if let time = try? await asset.load(.duration), time.seconds.isFinite { item.duration = time.seconds }
            else { item.duration = elapsed }
            do { try store.update(item); status = "录音已保存" }
            catch { errorMessage = "音频已保留，但文件信息保存失败：\(error.localizedDescription)" }
        }
        RecordingActivity.end()
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = .saved
    }

    private func pushActivity(force: Bool) {
        guard state == .recording || state == .paused else { return }
        let now = Date()
        if !force, let last = lastActivityUpdate, now.timeIntervalSince(last) < 0.35 { return }
        lastActivityUpdate = now
        let snippet = lines.last?.text ?? (state == .paused ? "已暂停" : "正在聆听…")
        let captions = lines.suffix(4).map { String($0.text.prefix(40)) }
        RecordingActivity.update(elapsed: elapsed, paused: state == .paused, snippet: String(snippet.prefix(80)), captions: captions.isEmpty ? [String(snippet.prefix(40))] : captions, levels: activityLevels)
    }

    private func applyBailian(_ text: String, finished: Bool) {
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }
        if finished {
            if lines.last?.provisional == true { lines.removeLast() }
            lines.append(TranscriptLine(time: elapsed, text: spoken, provisional: false))
        } else if lines.last?.provisional == true {
            lines[lines.count - 1].text = spoken
        } else {
            lines.append(TranscriptLine(time: elapsed, text: spoken, provisional: true))
        }
        pushActivity(force: true)
    }

    func addMark() {
        guard state == .recording || state == .paused else { return }
        marks.append(RecordingMark(id: UUID(), time: elapsed, note: ""))
        status = "已标记 \(Recording.compactTime(elapsed))"
    }

    private func sampleLevel() {
        guard state == .recording else { return }
        let value = levelMeter.get()
        levels.removeFirst()
        levels.append(value)
        activityLevels.removeFirst()
        activityLevels.append(Double(value))
    }
}

final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0
    func set(_ newValue: Float) { lock.lock(); value = newValue; lock.unlock() }
    func get() -> Float { lock.lock(); defer { lock.unlock() }; return value }
}
