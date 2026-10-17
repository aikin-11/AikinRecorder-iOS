import AVFoundation
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class LibraryStore {
    private(set) var recordings: [Recording] = []
    var errorMessage: String?
    let directory: URL
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
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw RecorderError.message("这个文件不包含可读取的音频。") }
        let duration = try await asset.load(.duration).seconds
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let id = UUID()
        let fileName = "\(id.uuidString).\(ext)"
        let target = directory.appendingPathComponent(fileName)
        try await Task.detached(priority: .userInitiated) {
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
        }.value
        let item = Recording(id: id, title: Recording.cleanTitle(source.deletingPathExtension().lastPathComponent),
                             fileName: fileName, createdAt: .now, duration: duration.isFinite ? duration : 0, transcript: "")
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
}

enum RecorderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
