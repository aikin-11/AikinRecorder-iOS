import Foundation

struct TranscriptLine: Identifiable, Equatable {
    let id: UUID
    var time: TimeInterval
    var text: String
    var provisional: Bool

    init(id: UUID = UUID(), time: TimeInterval, text: String, provisional: Bool) {
        self.id = id
        self.time = time
        self.text = text
        self.provisional = provisional
    }
}
