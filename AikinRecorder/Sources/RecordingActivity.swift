import ActivityKit
import Foundation

struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var elapsed: TimeInterval
        var paused: Bool
        var snippet: String
    }

    var title: String
}

enum RecordingActivity {
    @MainActor
    static func start(title: String, elapsed: TimeInterval) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RecordingActivityAttributes(title: title)
        let state = RecordingActivityAttributes.ContentState(elapsed: elapsed, paused: false, snippet: "正在聆听…")
        _ = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil), pushType: nil)
    }

    @MainActor
    static func update(elapsed: TimeInterval, paused: Bool, snippet: String) {
        let state = RecordingActivityAttributes.ContentState(elapsed: elapsed, paused: paused, snippet: snippet)
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in Activity<RecordingActivityAttributes>.activities {
            Task { await activity.update(content) }
        }
    }

    @MainActor
    static func end() {
        let state = RecordingActivityAttributes.ContentState(elapsed: 0, paused: true, snippet: "已保存")
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in Activity<RecordingActivityAttributes>.activities {
            Task { await activity.end(content, dismissalPolicy: .immediate) }
        }
    }
}
