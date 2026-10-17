import Foundation

enum BailianSettings {
    static let modelName = "qwen-audio-3.1-asr-flash-streaming"
    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: "bailian.apiKey") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "bailian.apiKey") }
    }
    static var model: String {
        get {
            let value = UserDefaults.standard.string(forKey: "bailian.model") ?? ""
            if value.isEmpty || value == "qwen-audio-asr-flash" { return modelName }
            return value
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "bailian.model") }
    }
    static func test() async throws {
        guard !apiKey.isEmpty else { throw RecorderError.message("请先填写阿里云百炼 API Key。") }
        guard let url = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/models") else {
            throw RecorderError.message("百炼地址无效。")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw RecorderError.message(detail.isEmpty ? "百炼连接失败。" : "百炼连接失败：\(detail.prefix(160))")
        }
    }

    static var endpoint: String {
        get {
            let value = UserDefaults.standard.string(forKey: "bailian.endpoint") ?? ""
            return value.isEmpty ? "wss://dashscope.aliyuncs.com/api-ws/v1/inference" : value
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "bailian.endpoint") }
    }
}

final class BailianRealtime: @unchecked Sendable {
    var onText: ((String, Bool) -> Void)?
    var onStatus: ((String) -> Void)?
    private let taskID = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(32)
    private var socket: URLSessionWebSocketTask?
    private var started = false
    private var pending = Data()
    private let lock = NSLock()
    private var receiver: Task<Void, Never>?

    func start() async throws {
        guard !BailianSettings.apiKey.isEmpty else { throw RecorderError.message("请先在设置中填写阿里云百炼 API Key。") }
        guard let url = URL(string: BailianSettings.endpoint) else { throw RecorderError.message("百炼 WebSocket 地址无效。") }
        var request = URLRequest(url: url)
        request.setValue("bearer \(BailianSettings.apiKey)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: request)
        socket = task
        task.resume()
        receiver = Task { [weak self] in await self?.receiveLoop() }
        try await sendJSON(runTask())
        onStatus?("正在连接阿里云百炼…")
    }

    func appendPCM(_ data: Data) {
        lock.lock()
        if started { lock.unlock(); socket?.send(.data(data)) { _ in } }
        else { pending.append(data); lock.unlock() }
    }

    func finish() async {
        try? await sendJSON([
            "header": ["action": "finish-task", "task_id": String(taskID), "streaming": "duplex"],
            "payload": ["input": [:] as [String: String]]
        ])
        try? await Task.sleep(for: .milliseconds(400))
        receiver?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
    }

    private func runTask() -> [String: Any] {
        [
            "header": ["action": "run-task", "task_id": String(taskID), "streaming": "duplex"],
            "payload": [
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": BailianSettings.model,
                "parameters": ["format": "pcm", "sample_rate": 16000],
                "input": [:] as [String: String]
            ]
        ]
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8), let socket else { return }
        try await socket.send(.string(text))
    }

    private func receiveLoop() async {
        while let socket, !Task.isCancelled {
            do {
                let message = try await socket.receive()
                let text: String
                switch message {
                case .string(let value): text = value
                case .data(let data): text = String(data: data, encoding: .utf8) ?? ""
                @unknown default: continue
                }
                handle(text)
            } catch { return }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let header = json["header"] as? [String: Any],
              let event = header["event"] as? String else { return }
        switch event {
        case "task-started":
            lock.lock()
            started = true
            let buffered = pending
            pending.removeAll()
            lock.unlock()
            if !buffered.isEmpty { socket?.send(.data(buffered)) { _ in } }
            onStatus?("百炼实时转写")
        case "result-generated":
            guard let payload = json["payload"] as? [String: Any],
                  let output = payload["output"] as? [String: Any],
                  let sentence = output["sentence"] as? [String: Any],
                  let spoken = sentence["text"] as? String else { return }
            let finished = (sentence["sentence_end"] as? Bool) == true
            onText?(spoken, finished)
        case "task-failed":
            let reason = header["error_message"] as? String ?? "未知错误"
            let lowered = reason.lowercased()
            if lowered.contains("token") || lowered.contains("quota") || lowered.contains("arrear") || lowered.contains("balance") || reason.contains("额度") || reason.contains("不足") || reason.contains("余额") {
                onStatus?("额度不足")
            } else {
                onStatus?("百炼转写失败：\(reason)")
            }
        default:
            break
        }
    }
}

final class BailianPCMSink: @unchecked Sendable {
    let downsampler: PCMDownsampler
    let service: BailianRealtime
    init(downsampler: PCMDownsampler, service: BailianRealtime) {
        self.downsampler = downsampler
        self.service = service
    }
}

final class PCMDownsampler: @unchecked Sendable {
    private var cursor: Double = 0
    func convert(_ samples: UnsafePointer<Float>, count: Int, sampleRate: Double) -> Data {
        guard count > 0, sampleRate > 0 else { return Data() }
        let step = sampleRate / 16_000
        var data = Data()
        data.reserveCapacity(count * 2)
        while cursor < Double(count) {
            let index = Int(cursor)
            let sample = max(-1, min(1, samples[index]))
            var value = Int16(sample * 32_767).littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
            cursor += step
        }
        cursor -= Double(count)
        return data
    }
}
