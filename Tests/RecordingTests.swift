import XCTest
@testable import AikinRecorder

final class RecordingTests: XCTestCase {
    func testMeetingNameUsesShanghaiTimeAndHasNoCollisionProneSequence() {
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: "2026-10-17T07:32:00Z")!
        XCTAssertEqual(Recording.meetingTitle(at: date), "Aikin会议录音_2026年10月17日15时32分")
    }

    func testTitlesCannotEscapeExportDirectory() {
        XCTAssertFalse(Recording.cleanTitle("../../private\n录音").contains("/"))
        XCTAssertFalse(Recording.cleanTitle("folder\\name").contains("\\"))
        XCTAssertFalse(Recording.cleanTitle(" \n ").isEmpty)
        XCTAssertEqual(Recording.cleanTitle(String(repeating: "会", count: 120)).count, 100)
    }

    func testDurationHandlesLongMeetingsAndInvalidMetadata() {
        XCTAssertEqual(Recording.timeText(3661), "01:01:01")
        XCTAssertEqual(Recording.timeText(-1), "00:00:00")
        XCTAssertEqual(Recording.timeText(.nan), "00:00:00")
    }

    @MainActor func testLibraryRoundTripAndTranscriptExport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        var item = try store.createDraft()
        item.title = "会议 / 纪要"
        item.transcript = "第一段会议记录。\n第二段会议记录。"
        item.duration = 90
        try Data([1, 2, 3]).write(to: store.audioURL(for: item))
        try store.update(item)
        let restored = LibraryStore(directory: directory)
        XCTAssertEqual(restored.recordings.count, 1)
        XCTAssertEqual(restored.recordings[0].transcript, item.transcript)
        let textURL = try store.shareText(item)
        XCTAssertEqual(try String(contentsOf: textURL, encoding: .utf8), item.transcript)
        XCTAssertEqual(textURL.pathExtension, "txt")
        try store.remove(item)
        XCTAssertTrue(store.recordings.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.audioURL(for: item).path))
        XCTAssertTrue(LibraryStore(directory: directory).recordings.isEmpty)
    }

    @MainActor func testRecoveryFindsAudioWithoutIndex() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([1]).write(to: directory.appendingPathComponent("orphan.m4a"))
        let store = LibraryStore(directory: directory)
        XCTAssertEqual(store.recordings.map(\.fileName), ["orphan.m4a"])
    }
}
