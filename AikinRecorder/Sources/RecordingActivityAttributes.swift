import ActivityKit
import Foundation

struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var elapsed: TimeInterval
        var paused: Bool
        var snippet: String
        var levels: [Double]
    }

    var title: String
}
