import Foundation

enum CustomModelSettings {
    static let defaultBase = "https://nas.aikin.site:8443/aikinday-test/v1"
    static let defaultModel = "Aikin-Personal"

    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: "custom.apiKey") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "custom.apiKey") }
    }

    static var model: String {
        get {
            let value = UserDefaults.standard.string(forKey: "custom.model") ?? ""
            return value.isEmpty ? defaultModel : value
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "custom.model") }
    }

    static var baseURL: String {
        get {
            let value = UserDefaults.standard.string(forKey: "custom.baseURL") ?? ""
            return value.isEmpty ? defaultBase : value
        }
        set {
            var value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            while value.hasSuffix("/") { value.removeLast() }
            UserDefaults.standard.set(value, forKey: "custom.baseURL")
        }
    }
}

enum CustomModelClient {
    static func test() async throws -> String {
        let (data, http) = try await send(path: "/models", method: "GET", body: nil, timeout: 20)
        guard (200..<300).contains(http.statusCode) else {
            throw RecorderError.message(errorText(data, fallback: "自定义模型连接失败。"))
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = (json?["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
        guard models.contains(CustomModelSettings.model) else {
            throw RecorderError.message(models.isEmpty ? "自定义模型没有返回可用模型。" : "接口里没有模型 \(CustomModelSettings.model)。")
        }
        return CustomModelSettings.model
    }

    static func summarize(transcript: String, onProgress: @escaping (Double) -> Void) async throws -> String {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecorderError.message("这条录音还没有转写文字，无法总结。")
        }
        let instructions = "你是会议记录助手。第一行必须是「主题：」加不超过16个字的内容主题。然后用中文整理结论、待办和关键发言。不要编造。必须遵守用户长期记忆里的人物、项目和偏好。"
        let memory = "以下是用户的长期记忆，之后的每次会议总结都必须遵守。涉及人物、偏好、项目和已确认事实时以此为准，不要忽略：\n\(MeetingMemory.prompt)"
        let text = try await complete(messages: [
            ["role": "system", "content": instructions],
            ["role": "system", "content": memory],
            ["role": "user", "content": String(transcript.prefix(700_000))]
        ], onProgress: onProgress)
        guard !text.isEmpty else { throw RecorderError.message("自定义模型没有返回总结。") }
        return text
    }

    static func ask(question: String, recordings: [Recording], onProgress: @escaping (Double) -> Void) async throws -> (answer: String, sources: [UUID]) {
        guard !recordings.isEmpty else { throw RecorderError.message("还没有录音可以提问。") }
        let corpus = recordings.prefix(12).map { item in
            let date = item.createdAt.formatted(date: .numeric, time: .shortened)
            return "[\(item.id.uuidString)] \(date) 时长\(Int(item.duration))秒 字数\(item.transcript.count) 标题：\(item.title)\n总结：\(item.summary.prefix(300))\n转写：\(item.transcript.prefix(1_200))"
        }.joined(separator: "\n\n")
        let instructions = "你是会议资料助手。先理解问题，再根据每条录音的日期、时长、字数、标题、总结和转写作统计或查找。必须遵守用户长期记忆里的人物、项目和偏好。先写答案，最后一行以「引用：」开头列出用到的 UUID，逗号分隔。"
        let content = try await complete(messages: [
            ["role": "system", "content": instructions],
            ["role": "user", "content": "用户长期记忆：\n\(MeetingMemory.prompt)\n\n问题：\(question)\n\n\(String(corpus.prefix(700_000)))"]
        ], onProgress: onProgress)
        var answer = content
        var sources: [UUID] = []
        if let range = content.range(of: "引用：") {
            answer = String(content[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            sources = content[range.upperBound...].split(separator: ",").compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        return (answer.isEmpty ? content : answer, sources)
    }

    private static func complete(messages: [[String: String]], onProgress: @escaping (Double) -> Void) async throws -> String {
        let payload: [String: Any] = [
            "model": CustomModelSettings.model,
            "stream": true,
            "messages": messages
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        guard body.count <= 1_000_000 else { throw RecorderError.message("发给自定义模型的内容超过 1MB。") }
        let (bytes, response) = try await open(path: "/chat/completions", body: body)
        guard let http = response as? HTTPURLResponse else { throw RecorderError.message("自定义模型没有返回结果。") }
        guard (200..<300).contains(http.statusCode) else {
            var raw = ""
            for try await line in bytes.lines { raw += line }
            let data = Data(raw.utf8)
            throw RecorderError.message(errorText(data, fallback: "自定义模型请求失败（\(http.statusCode)）。"))
        }
        onProgress(0.08)
        var collected = ""
        var ticks = 0
        for try await line in bytes.lines {
            if line.hasPrefix(":") {
                ticks += 1
                onProgress(min(0.9, 0.08 + Double(ticks) * 0.02))
                continue
            }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                throw RecorderError.message(message)
            }
            guard let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let piece = delta["content"] as? String else { continue }
            collected += piece
            onProgress(min(0.98, 0.9 + Double(collected.count) / 4_000))
        }
        onProgress(1)
        return collected.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func send(path: String, method: String, body: Data?, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await open(path: path, method: method, body: body, timeout: timeout)
        var data = Data()
        for try await byte in bytes { data.append(byte) }
        guard let http = response as? HTTPURLResponse else { throw RecorderError.message("自定义模型没有返回结果。") }
        return (data, http)
    }

    private static func open(path: String, method: String = "POST", body: Data? = nil, timeout: TimeInterval = 600) async throws -> (URLSession.AsyncBytes, URLResponse) {
        guard !CustomModelSettings.apiKey.isEmpty else { throw RecorderError.message("请先在设置中填写自定义模型 API Key。") }
        guard let url = URL(string: CustomModelSettings.baseURL + path) else { throw RecorderError.message("自定义模型地址无效。") }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(CustomModelSettings.apiKey)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return try await URLSession.shared.bytes(for: request)
    }

    private static func errorText(_ data: Data, fallback: String) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String, !message.isEmpty {
            return "自定义模型连接失败：\(message)"
        }
        let detail = String(data: data, encoding: .utf8) ?? ""
        return detail.isEmpty ? fallback : "自定义模型连接失败：\(detail.prefix(160))"
    }
}
