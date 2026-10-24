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
            return value.isEmpty ? "/存储空间1/AikinRecorder" : value
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "webdav.path") }
    }
    static var autoSync: Bool {
        get { UserDefaults.standard.bool(forKey: "webdav.auto") }
        set { UserDefaults.standard.set(newValue, forKey: "webdav.auto") }
    }
    static var syncMinute: Int {
        get {
            guard UserDefaults.standard.object(forKey: "webdav.minute") != nil else { return -1 }
            return UserDefaults.standard.integer(forKey: "webdav.minute")
        }
        set { UserDefaults.standard.set(newValue, forKey: "webdav.minute") }
    }
    static var lastSync: Date? {
        get { UserDefaults.standard.object(forKey: "webdav.last") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "webdav.last") }
    }
}

enum WebDAVSync {
    @MainActor
    static func syncIfDue(_ store: LibraryStore) async {
        let minute = WebDAVSettings.syncMinute
        guard minute >= 0 else { return }
        let calendar = Calendar.current
        var parts = calendar.dateComponents([.year, .month, .day], from: .now)
        parts.hour = minute / 60
        parts.minute = minute % 60
        guard let due = calendar.date(from: parts), Date() >= due else { return }
        if let last = WebDAVSettings.lastSync, last >= due { return }
        try? await sync(store)
    }

    static func test() async throws {
        _ = try await request(method: "PROPFIND", path: "", body: nil, depth: "0")
    }

    @MainActor
    static func sync(_ store: LibraryStore) async throws {
        try await test()
        try await ensureFolder(WebDAVSettings.remotePath)
        let present = Set(parseResponses(try await request(method: "PROPFIND", path: WebDAVSettings.remotePath, body: propfindBody, depth: "1")).map {
            normalized($0.path).split(separator: "/").last.map(String.init) ?? ""
        })
        for item in store.recordings {
            let name = Recording.cleanTitle(item.title)
            if present.contains(name) { continue }
            let folder = WebDAVSettings.remotePath + "/" + name
            try await ensureFolder(folder)
            let audio = store.audioURL(for: item)
            if FileManager.default.fileExists(atPath: audio.path) {
                try await upload(file: audio, folder: folder, remoteName: "录音.\(audio.pathExtension)")
            }
            if !item.transcript.isEmpty {
                let text = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.id.uuidString).txt")
                try Recording.exportText(lines: item.lines, fallback: item.transcript).write(to: text, atomically: true, encoding: .utf8)
                try await upload(file: text, folder: folder, remoteName: "转写.txt")
            }
            if !item.summary.isEmpty {
                let text = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.id.uuidString)-summary.txt")
                try item.summary.write(to: text, atomically: true, encoding: .utf8)
                try await upload(file: text, folder: folder, remoteName: "总结.txt")
            }
        }
        WebDAVSettings.lastSync = .now
    }

    static func backups() async throws -> [WebDAVBackup] {
        let listing = try await request(method: "PROPFIND", path: WebDAVSettings.remotePath, body: propfindBody, depth: "1")
        let parent = normalized(WebDAVSettings.remotePath)
        var result: [WebDAVBackup] = []
        for entry in parseResponses(listing) {
            let key = normalized(entry.path)
            guard !key.isEmpty, key != parent else { continue }
            let child = key.hasPrefix(parent + "/") || !key.contains("/") || key.hasSuffix("/" + (parent.split(separator: "/").last.map(String.init) ?? parent))
            guard parent.isEmpty || child || key.contains(parent) else { continue }
            let full = key.hasPrefix(parent) ? "/" + key : WebDAVSettings.remotePath + "/" + (key.split(separator: "/").last.map(String.init) ?? key)
            if entry.isCollection {
                let children = (try? parseResponses(await request(method: "PROPFIND", path: full, body: propfindBody, depth: "1"))) ?? []
                let bytes = children.filter { !$0.isCollection }.reduce(Int64(0)) { $0 + $1.bytes }
                result.append(WebDAVBackup(path: full, name: key.split(separator: "/").last.map(String.init) ?? key, bytes: bytes))
            } else {
                result.append(WebDAVBackup(path: full, name: key.split(separator: "/").last.map(String.init) ?? key, bytes: entry.bytes))
            }
        }
        return result
    }

    static func deleteBackups(_ paths: [String]) async throws {
        for path in paths {
            _ = try await request(method: "DELETE", path: path, body: nil, depth: nil)
        }
    }

    private static var propfindBody: Data {
        Data("""
        <?xml version="1.0"?><D:propfind xmlns:D="DAV:"><D:prop><D:getcontentlength/><D:resourcetype/></D:prop></D:propfind>
        """.utf8)
    }

    private static func normalized(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func parseResponses(_ data: Data) -> [(path: String, bytes: Int64, isCollection: Bool)] {
        let xml = String(data: data, encoding: .utf8) ?? ""
        guard let regex = try? NSRegularExpression(pattern: "<[^>]*:?response\\b[^>]*>([\\s\\S]*?)</[^>]*:?response>", options: [.caseInsensitive]) else { return [] }
        let range = NSRange(xml.startIndex..., in: xml)
        return regex.matches(in: xml, range: range).compactMap { match in
            guard let blockRange = Range(match.range(at: 1), in: xml) else { return nil }
            let block = String(xml[blockRange])
            guard let hrefRegex = try? NSRegularExpression(pattern: "<[^>]*:?href>([^<]+)", options: [.caseInsensitive]),
                  let hrefMatch = hrefRegex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
                  let hrefRange = Range(hrefMatch.range(at: 1), in: block) else { return nil }
            var href = String(block[hrefRange]).removingPercentEncoding ?? ""
            if href.contains("://"), let path = URL(string: href)?.path { href = path }
            let lengthRegex = try? NSRegularExpression(pattern: "<[^>]*:?getcontentlength>(\\d+)", options: [.caseInsensitive])
            let bytes = lengthRegex.flatMap { pattern in
                pattern.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)).flatMap { Range($0.range(at: 1), in: block) }.flatMap { Int64(block[$0]) }
            } ?? 0
            return (path: href, bytes: bytes, isCollection: block.range(of: "collection", options: .caseInsensitive) != nil)
        }
    }

    private static func ensureFolder(_ fullPath: String) async throws {
        let parts = fullPath.split(separator: "/").map(String.init)
        var current = ""
        for part in parts {
            current += "/" + part
            if (try? await request(method: "PROPFIND", path: current, body: nil, depth: "0")) != nil { continue }
            do { _ = try await request(method: "MKCOL", path: current, body: nil, depth: nil) }
            catch {
                throw RecorderError.message("无法在「\(current)」创建目录。根目录不能新建文件夹，请把保存位置改为 /存储空间1/AikinRecorder。")
            }
        }
    }

    private static func upload(file: URL, folder: String, remoteName: String) async throws {
        let data = try Data(contentsOf: file)
        _ = try await request(method: "PUT", path: folder + "/" + remoteName, body: data, depth: nil)
    }

    private static func request(method: String, path: String, body: Data?, depth: String?) async throws -> Data {
        guard var url = URL(string: WebDAVSettings.url), !WebDAVSettings.url.isEmpty else {
            throw RecorderError.message("请先填写 WebDAV 地址。")
        }
        for part in path.split(separator: "/") where !part.isEmpty {
            url.appendPathComponent(String(part))
        }
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

struct WebDAVBackup: Identifiable, Hashable {
    var id: String { path }
    var path: String
    var name: String
    var bytes: Int64
}

private extension String {
    func slice(after start: String, before end: String) -> String {
        guard let lower = range(of: start), let upper = range(of: end) else { return "" }
        return String(self[lower.upperBound..<upper.lowerBound])
    }
}
