import Foundation

struct Recording: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var fileName: String
    var createdAt: Date
    var duration: TimeInterval
    var transcript: String

    static func meetingTitle(at date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "'Aikin会议录音_'yyyy'年'MM'月'dd'日'HH'时'mm'分'"
        return formatter.string(from: date)
    }

    static func cleanTitle(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:\n\r\0")
        let clean = value.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((clean.isEmpty ? meetingTitle() : clean).prefix(100))
    }

    static func timeText(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
}
