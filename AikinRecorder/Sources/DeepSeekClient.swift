import Foundation

enum MeetingMemory {
    static var text: String {
        get { UserDefaults.standard.string(forKey: "ds.memory") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "ds.memory") }
    }
}

enum DeepSeekSettings {
    static let keyName = "deepseek.apiKey"
    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: keyName) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: keyName) }
    }
}

enum DeepSeekClient {
    static func test() async throws {
        let key = DeepSeekSettings.apiKey
        guard !key.isEmpty else { throw RecorderError.message("请先填写 DeepSeek API Key。") }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/models")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw RecorderError.message(detail.isEmpty ? "DeepSeek 连接失败。" : "DeepSeek 连接失败：\(detail.prefix(160))")
        }
    }

    static func summarize(transcript: String, onProgress: @escaping (Double) -> Void) async throws -> String {
        let key = DeepSeekSettings.apiKey
        guard !key.isEmpty else { throw RecorderError.message("请先在设置中填写 DeepSeek API Key。") }
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecorderError.message("这条录音还没有转写文字，无法总结。")
        }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": "deepseek-chat",
            "stream": true,
            "messages": [
                ["role": "system", "content": "你是会议记录助手。第一行必须是「主题：」加不超过16个字的内容主题。然后用中文整理结论、待办和关键发言。不要编造。已知记忆：\(MeetingMemory.text)"],
                ["role": "user", "content": String(transcript.prefix(24_000))]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RecorderError.message("DeepSeek 请求失败。")
        }
        onProgress(0)
        var collected = ""
        let estimate = max(600.0, Double(min(transcript.count, 24_000)) / 6)
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let piece = delta["content"] as? String else { continue }
            collected += piece
            onProgress(min(0.98, Double(collected.count) / estimate))
        }
        let summary = collected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { throw RecorderError.message("DeepSeek 没有返回总结。") }
        onProgress(1)
        return summary
    }

    static func theme(from summary: String) -> String {
        let lines = summary.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let marked = lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("主题：") }
        let line = marked ?? lines.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        let stripped = line.replacingOccurrences(of: "主题：", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "#* "))
        return String(stripped.prefix(16))
    }

    static func reviseMemory(_ note: String) async throws -> String {
        try await complete(system: "你维护一份给会议助手用的记忆。根据用户的新说明修正错误、补充事实，输出更新后的完整记忆。用简短中文，不要寒暄。", user: "当前记忆：\n\(MeetingMemory.text)\n\n新说明：\n\(note)")
    }

    private static func complete(system: String, user: String) async throws -> String {
        let key = DeepSeekSettings.apiKey
        guard !key.isEmpty else { throw RecorderError.message("请先填写 DeepSeek API Key。") }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["model": "deepseek-chat", "messages": [["role": "system", "content": system], ["role": "user", "content": user]]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw RecorderError.message("DeepSeek 没有返回内容。")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func ask(question: String, recordings: [Recording]) async throws -> (answer: String, sources: [UUID]) {
        let key = DeepSeekSettings.apiKey
        guard !key.isEmpty else { throw RecorderError.message("请先在设置中填写 DeepSeek API Key。") }
        guard !recordings.isEmpty else { throw RecorderError.message("还没有录音可以提问。") }
        let corpus = recordings.prefix(20).map { item in
            let date = item.createdAt.formatted(date: .numeric, time: .shortened)
            return "[\(item.id.uuidString)] \(date) 时长\(Int(item.duration))秒 字数\(item.transcript.count) 标题：\(item.title)\n总结：\(item.summary.prefix(400))\n转写：\(item.transcript.prefix(2_000))"
        }.joined(separator: "\n\n")
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": "deepseek-chat",
            "messages": [
                ["role": "system", "content": "你是会议资料助手。先理解问题，再根据每条录音的日期、时长、字数、标题、总结和转写作统计或查找，不要只匹配关键词。可以回答这周开了几次会、转写了多少字、最长会议是什么时候、讲了什么，也可以按主题找录音。先写答案，最后一行以「引用：」开头列出用到的 UUID，逗号分隔。已知记忆：\(MeetingMemory.text)"],
                ["role": "user", "content": "问题：\(question)\n\n\(corpus.prefix(24_000))"]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RecorderError.message("DeepSeek 回答失败。")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw RecorderError.message("DeepSeek 没有返回答案。")
        }
        var answer = content
        var sources: [UUID] = []
        if let range = content.range(of: "引用：") {
            answer = String(content[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = content[range.upperBound...]
            sources = tail.split(separator: ",").compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        return (answer.isEmpty ? content : answer, sources)
    }
}
