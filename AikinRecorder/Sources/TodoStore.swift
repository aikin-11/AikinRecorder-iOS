import Foundation

struct TodoItem: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var done: Bool
    var recordingID: UUID?
    var createdAt: Date
}

enum TodoParser {
    static func titles(in summary: String) -> [String] {
        let lines = summary.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var collecting = false
        var foundSection = false
        var titles: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if isSection(line) {
                collecting = line.contains("待办")
                if collecting { foundSection = true }
                continue
            }
            if collecting || (!foundSection && line.contains("待办")) {
                if let title = item(line), !title.isEmpty { titles.append(title) }
            }
        }
        if titles.isEmpty {
            titles = lines.compactMap { raw -> String? in
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard line.contains("[ ]") || line.contains("[x]") || line.contains("[X]") else { return nil }
                return item(line)
            }
        }
        var seen = Set<String>()
        return titles.filter { seen.insert($0).inserted }
    }

    private static func isSection(_ line: String) -> Bool {
        if line.hasPrefix("#") { return true }
        let plain = line.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces)
        return plain.hasSuffix("：") || plain.hasSuffix(":")
    }

    private static func item(_ line: String) -> String? {
        var text = line
        for prefix in ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* ", "- ", "• ", "+ "] {
            if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)); break }
        }
        if let match = text.range(of: #"^\d+[.、]\s*"#, options: .regularExpression) {
            text = String(text[match.upperBound...])
        }
        text = text.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces)
        guard text.count >= 2, text.count <= 80 else { return nil }
        if text.hasPrefix("|") || text.contains("---") { return nil }
        return text
    }
}
