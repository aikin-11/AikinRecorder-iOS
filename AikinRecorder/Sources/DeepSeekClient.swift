import Foundation

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

    static func summarize(transcript: String) async throws -> String {
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
            "messages": [
                ["role": "system", "content": "你是会议记录助手。请用中文根据转写整理会议总结，包含结论、待办和关键发言要点。不要编造转写中没有的事实。"],
                ["role": "user", "content": String(transcript.prefix(24_000))]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw RecorderError.message(detail.isEmpty ? "DeepSeek 请求失败。" : "DeepSeek 请求失败：\(detail.prefix(180))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw RecorderError.message("DeepSeek 没有返回总结。")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
