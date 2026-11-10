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
    private var markFlashUntil = Date.distantPast
    private var aliveTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundObserver: NSObjectProtocol?
    private var sealedParts: [URL] = []
    private var openPart: URL?
    private var fileSealed = false

    var transcript: String {
        lines.filter { !$0.provisional }.map(\.text).joined(separator: "\n")
    }

    var hasUnsavedRecording: Bool { state == .recording || state == .paused || state == .saving }

    func start(in store: LibraryStore) async {
        guard state == .idle else { return }
        state = .preparing
        transcriptionEngine = "local"
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
            if liveTranscription {
                let service = SpeechSession()
                service.clock = { [weak self] in self?.elapsed ?? 0 }
                service.onLines = { [weak self] lines in
                    Task { @MainActor in
                        self?.lines = lines
                        self?.pushActivity(force: false)
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
                onFailure: { [weak self, weak store] message in Task { @MainActor in
                    self?.errorMessage = "音频写入失败：\(message)"
                    if let self, let store { await self.finish(in: store) }
                } })
            capture = pipeline
            openPart = store.audioURL(for: draft)
            fileSealed = false
            input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in pipeline.append(buffer) }
            hasTap = true
            engine.prepare()
            try engine.start()
            state = .recording
            startTime = .now
            UIApplication.shared.isIdleTimerDisabled = true
            holdAlive()
            backgroundObserver = NotificationCenter.default.addObserver(forName: .aikinEnterBackground, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if self.state == .paused { await self.sealAndCheckpoint(in: store) }
                    else { self.reinforceSession() }
                }
            }
            RecordingActivity.start(title: Recording.cleanTitle(title), elapsed: 0)
            markObserver = NotificationCenter.default.addObserver(forName: .aikinRecordingMark, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.addMark() }
            }
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self else { return }
                    if self.state == .recording, let start = self.startTime { self.elapsed = self.elapsedBeforePause + Date().timeIntervalSince(start) }
                    if Int(self.elapsed) % 20 == 0 { self.holdAlive() }
                    self.pushActivity(force: false)
                }
            }
            interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                object: nil, queue: .main) { [weak self] notification in
                    let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                    let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    Task { @MainActor in
                        guard let self, self.state == .recording || self.state == .paused else { return }
                        if raw == AVAudioSession.InterruptionType.began.rawValue {
                            if self.state == .recording {
                                self.engine.pause()
                                self.elapsedBeforePause = self.elapsed
                                self.startTime = nil
                                self.state = .paused
                                await self.sealAndCheckpoint(in: store)
                            }
                            self.status = "系统短暂占用了麦克风，这段录音已保存。结束后会自动继续。"
                            self.reinforceSession()
                            self.pushActivity(force: true)
                        } else if options & AVAudioSession.InterruptionOptions.shouldResume.rawValue != 0, self.state == .paused {
                            try? AVAudioSession.sharedInstance().setActive(true)
                            if await self.reopenWriter(in: store) {
                                try? self.engine.start()
                                self.startTime = .now
                                self.state = .recording
                            }
                            self.status = "已继续录音"
                            self.reinforceSession()
                            self.pushActivity(force: true)
                        }
                    }
                }
        } catch {
            engine.stop()
            if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
            await capture?.close()
            capture = nil
            await speech?.cancel()
            speech = nil
            if let item { try? store.remove(item) }
            item = nil
            state = .idle
            errorMessage = error.localizedDescription
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }

    func togglePause(in store: LibraryStore) async {
        if state == .recording {
            engine.pause()
            elapsedBeforePause = elapsed
            startTime = nil
            state = .paused
            await sealAndCheckpoint(in: store)
            pushActivity(force: true)
        } else if state == .paused {
            do {
                guard await reopenWriter(in: store) else { return }
                try AVAudioSession.sharedInstance().setActive(true)
                try engine.start()
                startTime = .now
                state = .recording
                status = "已继续录音"
                pushActivity(force: true)
            } catch {
                state = .paused
                startTime = nil
                errorMessage = "暂时无法继续录音，已暂停的内容还在。可以点完成保存，或稍后再试继续。"
            }
        }
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
        await capture?.seal()
        if let openPart, !fileSealed { sealedParts.append(openPart) }
        fileSealed = true
        openPart = nil
        await mergePartsIfNeeded(in: store)
        await capture?.close()
        capture = nil
        await speech?.finishLive()
        speech = nil
        if let observer = interruptionObserver { NotificationCenter.default.removeObserver(observer); interruptionObserver = nil }
        if let observer = markObserver { NotificationCenter.default.removeObserver(observer); markObserver = nil }
        if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer); backgroundObserver = nil }
        if var item {
            item.title = Recording.cleanTitle(title)
            item.transcript = transcript
            item.lines = lines.filter { !$0.provisional }.map { TranscriptCue(id: $0.id, time: $0.time, text: $0.text) }
            item.marks = marks
            let asset = AVURLAsset(url: store.audioURL(for: item))
            if let time = try? await asset.load(.duration), time.seconds.isFinite, time.seconds > 0 { item.duration = time.seconds }
            else { item.duration = max(elapsed, elapsedBeforePause) }
            do { try store.update(item); status = "录音已保存" }
            catch { errorMessage = "音频已保留，但文件信息保存失败：\(error.localizedDescription)" }
            let savedID = item.id
            store.beginMeetingSummary(savedID)
        }
        RecordingActivity.end()
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = .saved
        endAlive()
    }

    func discard(in store: LibraryStore) async {
        guard state == .recording || state == .paused else { return }
        state = .saving
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "DiscardRecording")
        defer { if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) } }
        await stopCapture()
        if let item { try? store.discardDraft(item) }
        item = nil
        RecordingActivity.end()
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = .saved
        endAlive()
    }

    private func stopCapture() async {
        timer?.cancel()
        timer = nil
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        await capture?.close()
        capture = nil
        await speech?.cancel()
        speech = nil
        if let observer = interruptionObserver { NotificationCenter.default.removeObserver(observer); interruptionObserver = nil }
        if let observer = markObserver { NotificationCenter.default.removeObserver(observer); markObserver = nil }
        if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer); backgroundObserver = nil }
    }

    private func reinforceSession() {
        guard state == .recording || state == .paused else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? session.setActive(true)
        if state == .recording, !engine.isRunning {
            startTime = .now
            try? engine.start()
        }
        holdAlive()
    }

    private func holdAlive() {
        guard state == .recording || state == .paused || state == .saving else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? session.setActive(true)
        if state == .recording, !engine.isRunning { try? engine.start() }
        let previous = aliveTask
        aliveTask = UIApplication.shared.beginBackgroundTask(withName: "KeepRecording") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let expired = self.aliveTask
                if self.state == .recording || self.state == .paused { self.reinforceSession() }
                if expired != .invalid { UIApplication.shared.endBackgroundTask(expired) }
                if self.aliveTask == expired { self.aliveTask = .invalid }
            }
        }
        if previous != .invalid, previous != aliveTask { UIApplication.shared.endBackgroundTask(previous) }
    }

    private func endAlive() {
        if aliveTask != .invalid {
            UIApplication.shared.endBackgroundTask(aliveTask)
            aliveTask = .invalid
        }
    }

    private func pushActivity(force: Bool) {
        guard state == .recording || state == .paused else { return }
        let now = Date()
        if !force, let last = lastActivityUpdate, now.timeIntervalSince(last) < 2 { return }
        lastActivityUpdate = now
        let snippet = lines.last?.text ?? (state == .paused ? "已暂停" : "正在聆听…")
        let captions = lines.suffix(4).map { String($0.text.prefix(40)) }
        RecordingActivity.update(elapsed: elapsed, paused: state == .paused, snippet: String(snippet.prefix(80)), captions: captions.isEmpty ? [String(snippet.prefix(40))] : captions, levels: activityLevels, markedUntil: markFlashUntil)
    }

    func addMark() {
        guard state == .recording || state == .paused else { return }
        let anchor = lines.min { abs($0.time - elapsed) < abs($1.time - elapsed) }
        let time = anchor?.time ?? elapsed
        marks.append(RecordingMark(id: UUID(), time: time, note: ""))
        markFlashUntil = Date().addingTimeInterval(2)
        status = "已标记 \(Recording.compactTime(time))"
        pushActivity(force: true)
    }

    private func sealAndCheckpoint(in store: LibraryStore) async {
        guard state == .paused || state == .recording else { return }
        let task = UIApplication.shared.beginBackgroundTask(withName: "SealRecording")
        defer { if task != .invalid { UIApplication.shared.endBackgroundTask(task) } }
        if !fileSealed {
            await capture?.seal()
            if let openPart { sealedParts.append(openPart) }
            fileSealed = true
            openPart = nil
        }
        await mergePartsIfNeeded(in: store)
        guard var item else { return }
        item.title = Recording.cleanTitle(title)
        item.transcript = transcript
        item.lines = lines.filter { !$0.provisional }.map { TranscriptCue(id: $0.id, time: $0.time, text: $0.text) }
        item.marks = marks
        let asset = AVURLAsset(url: store.audioURL(for: item))
        if let time = try? await asset.load(.duration), time.seconds.isFinite, time.seconds > 0 {
            item.duration = time.seconds
            elapsedBeforePause = max(elapsedBeforePause, elapsed, time.seconds)
            elapsed = max(elapsed, time.seconds)
        } else if elapsed > 0 {
            item.duration = elapsed
        }
        self.item = item
        do { try store.update(item) }
        catch { errorMessage = "录音已暂停，但时长没能写入列表：\(error.localizedDescription)" }
        status = "已暂停，录音已保存"
    }

    private func reopenWriter(in store: LibraryStore) async -> Bool {
        guard fileSealed else { return true }
        guard let capture, let item else {
            errorMessage = "暂时无法继续录音，已暂停的内容还在。可以点完成保存。"
            return false
        }
        let next = store.directory.appendingPathComponent("\(item.id.uuidString)-part-\(sealedParts.count).m4a")
        do {
            try await capture.beginFile(at: next)
            openPart = next
            fileSealed = false
            return true
        } catch {
            errorMessage = "暂时无法继续录音，已暂停的内容还在。可以点完成保存，或稍后再试继续。"
            return false
        }
    }

    private func mergePartsIfNeeded(in store: LibraryStore) async {
        guard sealedParts.count > 1, let item else { return }
        let destination = store.audioURL(for: item)
        do {
            try await RecordingMerger.merge(sealedParts, into: destination)
            for url in sealedParts where url != destination { try? FileManager.default.removeItem(at: url) }
            sealedParts = [destination]
        } catch {
            errorMessage = "前面的录音已保留，合并后半段时出错：\(error.localizedDescription)"
        }
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

enum RecordingMerger {
    static func merge(_ parts: [URL], into destination: URL) async throws {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw RecorderError.message("无法合并暂停前后的录音。")
        }
        var cursor = CMTime.zero
        for url in parts {
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let duration = try await asset.load(.duration)
            guard duration.seconds > 0 else { continue }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: cursor)
            cursor = cursor + duration
        }
        guard cursor.seconds > 0 else { throw RecorderError.message("没有可合并的录音。") }
        let temp = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + "-merged.m4a")
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecorderError.message("无法导出合并后的录音。")
        }
        export.outputURL = temp
        export.outputFileType = .m4a
        try await export.export(to: temp, as: .m4a)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temp, to: destination)
    }
}

final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0
    func set(_ newValue: Float) { lock.lock(); value = newValue; lock.unlock() }
    func get() -> Float { lock.lock(); defer { lock.unlock() }; return value }
}
