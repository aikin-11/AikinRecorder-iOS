import Foundation

enum WebDAVSettings {
    static var url: String {
        get { UserDefaults.standard.string(forKey: "webdav.url") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "webdav.url") }
    }
    static var username: String {
        get { UserDefaults.standard.string(forKey: "webdav.user") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "webdav.user") }
    }
    static var password: String {
        get { UserDefaults.standard.string(forKey: "webdav.password") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "webdav.password") }
    }
    static var remotePath: String {
        get {
            let value = UserDefaults.standard.string(forKey: "webdav.path") ?? "/AikinRecorder"
            return value.isEmpty ? "/AikinRecorder" : value
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "webdav.path") }
    }
    static var autoSync: Bool {
        get { UserDefaults.standard.bool(forKey: "webdav.auto") }
        set { UserDefaults.standard.set(newValue, forKey: "webdav.auto") }
    }
    static var intervalHours: Int {
        get { max(0, UserDefaults.standard.integer(forKey: "webdav.hours")) }
        set { UserDefaults.standard.set(newValue, forKey: "webdav.hours") }
    }
    static var lastSync: Date? {
        get { UserDefaults.standard.object(forKey: "webdav.last") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "webdav.last") }
    }
}

enum WebDAVSync {
    @MainActor
    static func syncIfDue(_ store: LibraryStore) async {
        guard WebDAVSettings.autoSync, WebDAVSettings.intervalHours > 0 else { return }
        if let last = WebDAVSettings.lastSync, Date().timeIntervalSince(last) < Double(WebDAVSettings.intervalHours) * 3600 { return }
        try? await sync(store)
    }

    static func test() async throws {
        _ = try await request(method: "PROPFIND", path: WebDAVSettings.remotePath, body: nil, depth: "0")
    }

    @MainActor
    static func sync(_ store: LibraryStore) async throws {
        try await test()
        try await ensureFolder()
        for item in store.recordings {
            let audio = store.audioURL(for: item)
            if FileManager.default.fileExists(atPath: audio.path) {
                try await upload(file: audio, remoteName: "\(item.id.uuidString).\(audio.pathExtension)")
            }
            if !item.transcript.isEmpty {
                let text = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.id.uuidString).txt")
                try item.transcript.write(to: text, atomically: true, encoding: .utf8)
                try await upload(file: text, remoteName: "\(item.id.uuidString).txt")
            }
            if !item.summary.isEmpty {
                let text = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.id.uuidString)-summary.txt")
                try item.summary.write(to: text, atomically: true, encoding: .utf8)
                try await upload(file: text, remoteName: "\(item.id.uuidString)-summary.txt")
            }
        }
        WebDAVSettings.lastSync = .now
    }

    private static func ensureFolder() async throws {
        let parts = WebDAVSettings.remotePath.split(separator: "/").map(String.init)
        var current = ""
        for part in parts {
            current += "/" + part
            _ = try? await request(method: "MKCOL", path: current, body: nil, depth: nil)
        }
    }

    private static func upload(file: URL, remoteName: String) async throws {
        let data = try Data(contentsOf: file)
        var path = WebDAVSettings.remotePath
        if !path.hasSuffix("/") { path += "/" }
        _ = try await request(method: "PUT", path: path + remoteName, body: data, depth: nil)
    }

    private static func request(method: String, path: String, body: Data?, depth: String?) async throws -> Data {
        guard let base = URL(string: WebDAVSettings.url), !WebDAVSettings.url.isEmpty else {
            throw RecorderError.message("请先填写 WebDAV 地址。")
        }
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = relative.isEmpty ? base : base.appendingPathComponent(relative)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let depth { request.setValue(depth, forHTTPHeaderField: "Depth") }
        if !WebDAVSettings.username.isEmpty {
            let raw = Data("\(WebDAVSettings.username):\(WebDAVSettings.password)".utf8).base64EncodedString()
            request.setValue("Basic \(raw)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) || http.statusCode == 405 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw RecorderError.message("WebDAV 连接失败（\(code)）。")
        }
        return data
    }
}
