import ActivityKit
import Foundation

enum RecordingActivity {
    @MainActor
    static func start(title: String, elapsed: TimeInterval) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RecordingActivityAttributes(title: title)
        let state = RecordingActivityAttributes.ContentState(elapsed: elapsed, paused: false, snippet: "正在聆听…", captions: ["正在聆听…"], levels: [0.2, 0.2, 0.2, 0.2, 0.2], markedUntil: .distantPast)
        _ = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil), pushType: nil)
    }

    @MainActor
    static func update(elapsed: TimeInterval, paused: Bool, snippet: String, captions: [String], levels: [Double], markedUntil: Date) {
        let state = RecordingActivityAttributes.ContentState(elapsed: elapsed, paused: paused, snippet: snippet, captions: captions, levels: levels, markedUntil: markedUntil)
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in Activity<RecordingActivityAttributes>.activities {
            Task { await activity.update(content) }
        }
    }

    @MainActor
    static func end() {
        let state = RecordingActivityAttributes.ContentState(elapsed: 0, paused: true, snippet: "已保存", captions: ["已保存"], levels: [], markedUntil: .distantPast)
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in Activity<RecordingActivityAttributes>.activities {
            Task { await activity.end(content, dismissalPolicy: .immediate) }
        }
    }
}
