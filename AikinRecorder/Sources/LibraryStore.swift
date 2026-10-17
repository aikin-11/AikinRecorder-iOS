import ActivityKit
import AVFoundation
import CryptoKit
import Observation
import UIKit
import UniformTypeIdentifiers

@MainActor @Observable
final class LibraryStore {
    private(set) var recordings: [Recording] = []
    var errorMessage: String?
    var transcribingID: UUID?
    var queuedIDs: Set<UUID> = []
    var transcriptProgress = 0.0
    var transcriptCursor: TimeInterval = 0
    var transcriptPaused = false
    var transcriptTick = 0
    let directory: URL
    private var speech: SpeechSession?
    private var transcriptionTask: Task<Void, Never>?
    private var transcriptionQueue: [(id: UUID, start: TimeInterval)] = []
    private var lastTranscriptSave: Date?
    private var latestLines: [TranscriptCue] = []
    private var silence: AVAudioPlayer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let indexURL: URL

    init(directory: URL? = nil) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? documents.appendingPathComponent("Recordings", isDirectory: true)
        indexURL = self.directory.appendingPathComponent("library.json")
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: self.directory.path)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                recordings = try JSONDecoder().decode([Recording].self, from: Data(contentsOf: indexURL))
            }
            recoverUnindexedAudio()
        } catch { errorMessage = "文件库读取失败：\(error.localizedDescription)" }
    }

    func audioURL(for recording: Recording) -> URL { directory.appendingPathComponent(recording.fileName) }

    private static func md5(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = Insecure.MD5()
        while true {
            let chunk = handle.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func createDraft() throws -> Recording {
        let id = UUID()
        let draft = Recording(id: id, title: Recording.meetingTitle(), fileName: "\(id.uuidString).m4a",
                              createdAt: .now, duration: 0, transcript: "")
        recordings.insert(draft, at: 0)
        try persist()
        return draft
    }

    func update(_ recording: Recording) throws {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        let previous = recordings[index]
        recordings[index] = recording
        do { try persist() } catch { recordings[index] = previous; throw error }
    }

    func remove(_ recording: Recording) throws {
        // Persist the index first. A failed file deletion is recoverable on next launch.
        let previous = recordings
        recordings.removeAll { $0.id == recording.id }
        do { try persist() } catch { recordings = previous; throw error }
        let url = audioURL(for: recording)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    func importAudio(from source: URL) async throws -> Recording {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let hash = try Self.md5(of: source)
        let bytes = ((try? FileManager.default.attributesOfItem(atPath: source.path)[.size]) as? NSNumber)?.int64Value ?? 0
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw RecorderError.message("这个文件不包含可读取的音频。") }
        let duration = try await asset.load(.duration).seconds
        let seconds = duration.isFinite ? duration : 0
        if recordings.contains(where: { item in
            if !hash.isEmpty && item.sourceHash == hash { return true }
            return bytes > 0 && item.sourceBytes == bytes && abs(item.duration - seconds) < 1
        }) {
            throw RecorderError.message("这份音频已经导入过，未再次复制。")
        }
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let id = UUID()
        let fileName = "\(id.uuidString).\(ext)"
        let target = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.copyItem(at: source, to: target)
        let item = Recording(id: id, title: Recording.cleanTitle(source.deletingPathExtension().lastPathComponent),
                             fileName: fileName, createdAt: .now, duration: seconds, transcript: "", sourceHash: hash, sourceBytes: bytes)
        recordings.insert(item, at: 0)
        do { try persist() } catch {
            recordings.removeAll { $0.id == id }
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        return item
    }

    func shareAudio(_ item: Recording) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Exports/\(item.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(Recording.cleanTitle(item.title)).appendingPathExtension(audioURL(for: item).pathExtension)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.copyItem(at: audioURL(for: item), to: target)
        return target
    }

    func fileBytes(_ recording: Recording) -> Int64 {
        let url = audioURL(for: recording)
        return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    func storageBytes() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func removeAll() throws {
        let previous = recordings
        recordings = []
        do { try persist() } catch { recordings = previous; throw error }
        for item in previous {
            let url = audioURL(for: item)
            if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
        }
    }

    func shareText(_ item: Recording) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Exports/\(item.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(Recording.cleanTitle(item.title)).appendingPathExtension("txt")
        try item.transcript.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func shareSummary(_ item: Recording) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Exports/\(item.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(Recording.cleanTitle(item.title) + "_会议总结").appendingPathExtension("txt")
        try item.summary.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func persist() throws {
        try JSONEncoder().encode(recordings).write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func recoverUnindexedAudio() {
        // A crash cannot make a completed audio file disappear from the library.
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let known = Set(recordings.map(\.fileName))
        for file in files where !known.contains(file.lastPathComponent) && ["m4a", "caf", "wav", "mp3", "aac", "aiff"].contains(file.pathExtension.lowercased()) {
            let date = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now
            recordings.append(Recording(id: UUID(), title: "恢复的录音_\(Recording.meetingTitle(at: date))", fileName: file.lastPathComponent, createdAt: date, duration: 0, transcript: ""))
        }
        recordings.sort { $0.createdAt > $1.createdAt }
        try? persist()
    }

    func beginTranscription(_ recording: Recording, from start: TimeInterval) {
        if transcribingID == recording.id || queuedIDs.contains(recording.id) { return }
        if transcribingID != nil {
            transcriptionQueue.append((recording.id, start))
            queuedIDs.insert(recording.id)
            return
        }
        startTranscriptionJob(recording, from: start)
    }

    private func startTranscriptionJob(_ recording: Recording, from start: TimeInterval) {
        var item = recording
        if start < 1 { item.lines = []; item.transcript = ""; item.transcribedThrough = 0 }
        let kept = item.lines
        transcribingID = item.id
        transcriptPaused = false
        transcriptCursor = start
        transcriptProgress = item.duration > 0 ? min(1, start / item.duration) : 0
        try? update(item)
        let service = SpeechSession()
        speech = service
        let duration = item.duration
        service.onProgress = { [weak self] seconds in
            guard let self else { return }
            let whole = duration > 1 ? duration : seconds
            self.transcriptCursor = seconds
            self.transcriptProgress = whole > 0 ? min(1, seconds / whole) : 0
            if let index = self.recordings.firstIndex(where: { $0.id == item.id }) {
                self.recordings[index].transcribedThrough = seconds
            }
            self.pushTranscriptActivity(title: item.title, fraction: self.transcriptProgress)
        }
        service.onLines = { [weak self] lines in
            guard let self, let index = self.recordings.firstIndex(where: { $0.id == item.id }) else { return }
            let fresh = lines.filter { !$0.provisional }.map {
                TranscriptCue(id: $0.id, time: max(0, $0.time), text: $0.text)
            }
            self.latestLines = kept + fresh
            let now = Date()
            guard self.lastTranscriptSave == nil || now.timeIntervalSince(self.lastTranscriptSave!) > 0.6 else { return }
            self.lastTranscriptSave = now
            self.recordings[index].lines = self.latestLines
            self.recordings[index].transcript = self.latestLines.map(\.text).joined(separator: "\n")
            self.transcriptTick += 1
            try? self.persist()
        }
        holdBackground()
        RecordingActivity.start(title: item.title, elapsed: 0)
        pushTranscriptActivity(title: item.title, fraction: transcriptProgress)
        transcriptionTask = Task { [weak self] in
            defer { self?.finishTranscription(for: item.id) }
            do {
                guard let self else { return }
                try await service.transcribeFile(self.audioURL(for: item), localeID: "zh-CN", from: start)
            } catch is CancellationError {
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func toggleTranscriptPause() {
        guard let id = transcribingID else { return }
        if !transcriptionQueue.isEmpty {
            if let index = recordings.firstIndex(where: { $0.id == id }) {
                recordings[index].transcribedThrough = speech?.submitted ?? recordings[index].transcribedThrough
                try? persist()
            }
            speech?.setFilePaused(true)
            transcriptionTask?.cancel()
            return
        }
        transcriptPaused.toggle()
        speech?.setFilePaused(transcriptPaused)
        if transcriptPaused {
            RecordingActivity.end()
            return
        }
        if let id = transcribingID, let index = recordings.firstIndex(where: { $0.id == id }) {
            recordings[index].transcribedThrough = speech?.submitted ?? recordings[index].transcribedThrough
            try? persist()
            pushTranscriptActivity(title: recordings[index].title, fraction: transcriptProgress)
        }
    }

    func hideIsland() {
        RecordingActivity.end()
    }

    private func pushTranscriptActivity(title: String, fraction: Double) {
        if Activity<RecordingActivityAttributes>.activities.isEmpty {
            RecordingActivity.start(title: title, elapsed: fraction)
        }
        let percent = "\(Int(fraction * 100))%"
        RecordingActivity.update(elapsed: fraction, paused: transcriptPaused, snippet: transcriptPaused ? "转写已暂停 \(percent)" : "正在转写 \(percent)", captions: [percent], levels: [], markedUntil: .distantPast, progress: fraction)
    }

    private func finishTranscription(for id: UUID) {
        guard transcribingID == id else { return }
        if let index = recordings.firstIndex(where: { $0.id == id }) {
            if !latestLines.isEmpty {
                recordings[index].lines = latestLines
                recordings[index].transcript = latestLines.map(\.text).joined(separator: "\n")
            }
            recordings[index].transcribedThrough = max(recordings[index].transcribedThrough, speech?.submitted ?? 0)
            transcriptTick += 1
            try? persist()
        }
        latestLines = []
        transcribingID = nil
        transcriptPaused = false
        speech = nil
        if !transcriptionQueue.isEmpty {
            let next = transcriptionQueue.removeFirst()
            queuedIDs.remove(next.id)
            if let recording = recordings.first(where: { $0.id == next.id }) {
                startTranscriptionJob(recording, from: next.start)
                return
            }
        }
        silence?.stop()
        silence = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        RecordingActivity.end()
    }

    private func silentLoop() -> URL? {
        let url = directory.appendingPathComponent("silence.caf")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000),
              let file = try? AVAudioFile(forWriting: url, settings: format.settings) else { return nil }
        buffer.frameLength = 8_000
        try? file.write(from: buffer)
        return url
    }

    private func holdBackground() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        if silence == nil, let url = silentLoop() {
            silence = try? AVAudioPlayer(contentsOf: url)
        }
        silence?.numberOfLoops = -1
        silence?.volume = 0
        silence?.play()
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "transcribe") { [weak self] in
                guard let self else { return }
                UIApplication.shared.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }
        }
    }
}

enum RecorderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
