import Foundation

struct RecordingMark: Codable, Hashable, Identifiable {
    var id: UUID
    var time: TimeInterval
    var note: String
}

struct TranscriptCue: Codable, Hashable, Identifiable {
    var id: UUID
    var time: TimeInterval
    var text: String
}

struct Recording: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var fileName: String
    var createdAt: Date
    var duration: TimeInterval
    var transcript: String
    var lines: [TranscriptCue]
    var summary: String
    var marks: [RecordingMark]
    var transcribedThrough: TimeInterval
    var sourceHash: String
    var sourceBytes: Int64

    enum CodingKeys: String, CodingKey {
        case id, title, fileName, createdAt, duration, transcript, lines, summary, marks, transcribedThrough, sourceHash, sourceBytes
    }

    init(id: UUID, title: String, fileName: String, createdAt: Date, duration: TimeInterval, transcript: String, lines: [TranscriptCue] = [], summary: String = "", marks: [RecordingMark] = [], transcribedThrough: TimeInterval = 0, sourceHash: String = "", sourceBytes: Int64 = 0) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.createdAt = createdAt
        self.duration = duration
        self.transcript = transcript
        self.lines = lines
        self.summary = summary
        self.marks = marks
        self.transcribedThrough = transcribedThrough
        self.sourceHash = sourceHash
        self.sourceBytes = sourceBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        fileName = try container.decode(String.self, forKey: .fileName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        transcript = try container.decode(String.self, forKey: .transcript)
        lines = try container.decodeIfPresent([TranscriptCue].self, forKey: .lines) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        marks = try container.decodeIfPresent([RecordingMark].self, forKey: .marks) ?? []
        transcribedThrough = try container.decodeIfPresent(TimeInterval.self, forKey: .transcribedThrough) ?? 0
        sourceHash = try container.decodeIfPresent(String.self, forKey: .sourceHash) ?? ""
        sourceBytes = try container.decodeIfPresent(Int64.self, forKey: .sourceBytes) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(duration, forKey: .duration)
        try container.encode(transcript, forKey: .transcript)
        try container.encode(lines, forKey: .lines)
        try container.encode(summary, forKey: .summary)
        try container.encode(marks, forKey: .marks)
        try container.encode(transcribedThrough, forKey: .transcribedThrough)
        try container.encode(sourceHash, forKey: .sourceHash)
        try container.encode(sourceBytes, forKey: .sourceBytes)
    }

    static func meetingTitle(at date: Date = .now) -> String {
        _ = date
        return "Aikin会议录音"
    }

    static func cleanTitle(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:\n\r\0")
        let clean = value.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((clean.isEmpty ? meetingTitle() : clean).prefix(100))
    }

    static func countText(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    static func timeText(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }

    static func compactTime(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        let hours = value / 3600
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, value / 60 % 60, value % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
