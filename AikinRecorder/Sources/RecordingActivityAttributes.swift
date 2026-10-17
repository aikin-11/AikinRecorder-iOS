import ActivityKit
import AppIntents
import Foundation

extension Notification.Name {
    static let aikinRecordingMark = Notification.Name("aikin.recording.mark")
}

struct AddMarkIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "标记"
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .aikinRecordingMark, object: nil)
        return .result()
    }
}

struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var elapsed: TimeInterval
        var paused: Bool
        var snippet: String
        var captions: [String]
        var levels: [Double]
    }

    var title: String
}
