import CryptoKit
import SwiftUI
import UIKit
import Foundation
import Network
import Security

enum ChatGPTAccount {
    private static let service = "app.aikin.recorder.chatgpt"
    static var email: String { string("email") }
    static var canUsePlan: Bool { !storedAccess.isEmpty && scopes().contains("chatgpt.tokens.use.direct") }

    static func signIn() async throws {
        let host = hostID()
        let client = issuedClientID().isEmpty ? "dynamic_agent_client" : issuedClientID()
        let verifier = randomToken()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL()
        let state = randomToken()
        let nonce = randomToken()
        let port = UInt16.random(in: 49152...65000)
        let redirect = "http://127.0.0.1:\(port)/auth/callback"
        var parts = [
            "client_id=\(client.urlQuery)",
            "response_type=code",
            "redirect_uri=\(redirect.urlQuery)",
            "scope=\("openid profile email offline_access resource.invoke chatgpt.tokens.use.direct".urlQuery)",
            "resource=\("https://api.openai.com/v1".urlQuery)",
            "state=\(state.urlQuery)",
            "nonce=\(nonce.urlQuery)",
            "code_challenge_method=S256",
            "code_challenge=\(challenge.urlQuery)",
            "ext_agent_host_id=\(host.urlQuery)"
        ]
        if client == "dynamic_agent_client" { parts.append("agent_name_hint=\("AikinRec".urlQuery)") }
        else if !email.isEmpty { parts.append("login_hint=\(email.urlQuery)") }
        guard let url = URL(string: "https://auth.openai.com/api/accounts/authorize?\(parts.joined(separator: "&"))") else {
            throw RecorderError.message("无法打开 ChatGPT 登录。")
        }
        let callback = try await LoopbackCallback.wait(port: port, open: url)
        guard callback["state"] == state else { throw RecorderError.message("ChatGPT 登录校验失败。") }
        if callback["error"] == "access_denied" { throw RecorderError.message("未允许使用 ChatGPT 套餐。") }
        guard let code = callback["code"], !code.isEmpty else { throw RecorderError.message("ChatGPT 没有返回授权码。") }
        let issued = callback["client_id"] ?? client
        guard issued != "dynamic_agent_client" else { throw RecorderError.message("ChatGPT 注册未完成。") }
        let form = [
            "grant_type": "authorization_code",
            "client_id": issued,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirect,
            "resource": "https://api.openai.com/v1"
        ]
        try await storeToken(try await tokenRequest(form), clientID: issued, host: host, nonce: nonce)
    }

    static func signOut() {
        for key in ["email", "subject", "client", "access", "refresh", "id", "scopes", "expiry"] { delete(key) }
    }

    static func accessToken() async throws -> String {
        if let expiry = Double(string("expiry")), Date().timeIntervalSince1970 + 60 < expiry, !storedAccess.isEmpty {
            return storedAccess
        }
        let refresh = string("refresh")
        guard !refresh.isEmpty else { throw RecorderError.message("请先在设置中登录 ChatGPT。") }
        let form = ["grant_type": "refresh_token", "client_id": issuedClientID(), "refresh_token": refresh, "resource": "https://api.openai.com/v1"]
        try await storeToken(try await tokenRequest(form), clientID: issuedClientID(), host: hostID(), nonce: nil)
        return storedAccess
    }

    private static func storeToken(_ json: [String: Any], clientID: String, host: String, nonce: String?) async throws {
        guard let access = json["access_token"] as? String, let idToken = json["id_token"] as? String else {
            throw RecorderError.message("ChatGPT 没有返回登录凭证。")
        }
        let claims = try await IDToken.check(idToken, audience: clientID, nonce: nonce)
        save("client", clientID)
        save("access", access)
        if let refresh = json["refresh_token"] as? String, !refresh.isEmpty { save("refresh", refresh) }
        save("id", idToken)
        save("email", claims.email)
        save("subject", claims.subject)
        save("scopes", (json["scope"] as? String) ?? "")
        let expires = json["expires_in"] as? Double ?? 3600
        save("expiry", String(Date().timeIntervalSince1970 + expires))
        _ = host
        if !scopes().contains("chatgpt.tokens.use.direct") {
            throw RecorderError.message("已登录，但没有允许使用 ChatGPT 套餐。请重新登录并同意。")
        }
    }

    private static func tokenRequest(_ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields.map { "\($0.key.urlQuery)=\($0.value.urlQuery)" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RecorderError.message("ChatGPT 登录失败。")
        }
        return json
    }

    private static func hostID() -> String {
        if let saved = UserDefaults.standard.string(forKey: "chatgpt.host"), !saved.isEmpty { return saved }
        let value = "urn:uuid:\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(value, forKey: "chatgpt.host")
        return value
    }
    private static func issuedClientID() -> String { string("client") }
    private static func scopes() -> Set<String> { Set(string("scopes").split(separator: " ").map(String.init)) }
    private static var storedAccess: String { string("access") }
    private static func randomToken() -> String { Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64URL() }
    private static func string(_ key: String) -> String { load(key) }
    private static func save(_ key: String, _ value: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var next = query
        next[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(next as CFDictionary, nil)
    }
    private static func load(_ key: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    private static func delete(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
    }
}

private enum IDToken {
    struct Claims { let subject: String; let email: String }
    static func check(_ token: String, audience: String, nonce: String?) async throws -> Claims {
        let parts = token.split(separator: ".")
        guard parts.count == 3, let payload = Data(base64URL: String(parts[1])),
              let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let subject = json["sub"] as? String else { throw RecorderError.message("ChatGPT 身份无效。") }
        if json["iss"] as? String != "https://auth.openai.com" { throw RecorderError.message("ChatGPT 身份来源无效。") }
        let aud = json["aud"] as? String ?? (json["aud"] as? [String])?.first
        if aud != audience { throw RecorderError.message("ChatGPT 身份不匹配。") }
        if let exp = json["exp"] as? Double, exp < Date().timeIntervalSince1970 { throw RecorderError.message("ChatGPT 登录已过期。") }
        if let nonce, json["nonce"] as? String != nonce { throw RecorderError.message("ChatGPT 登录校验失败。") }
        try await verify(token, header: String(parts[0]), signing: String(parts[0]) + "." + String(parts[1]), signature: String(parts[2]))
        return Claims(subject: subject, email: json["email"] as? String ?? "")
    }

    private static func verify(_ token: String, header: String, signing: String, signature: String) async throws {
        guard let headerData = Data(base64URL: header),
              let headerJSON = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let kid = headerJSON["kid"] as? String,
              let signatureData = Data(base64URL: signature) else { throw RecorderError.message("ChatGPT 身份无效。") }
        let (configData, _) = try await URLSession.shared.data(from: URL(string: "https://auth.openai.com/.well-known/openid-configuration")!)
        let config = try JSONSerialization.jsonObject(with: configData) as? [String: Any]
        let jwksURL = URL(string: config?["jwks_uri"] as? String ?? "https://auth.openai.com/.well-known/jwks.json")!
        let (data, _) = try await URLSession.shared.data(from: jwksURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keys = json["keys"] as? [[String: Any]],
              let key = keys.first(where: { $0["kid"] as? String == kid }),
              let n = key["n"] as? String, let e = key["e"] as? String,
              let modulus = Data(base64URL: n), let exponent = Data(base64URL: e),
              let publicKey = rsaKey(modulus: modulus, exponent: exponent) else { throw RecorderError.message("无法核对 ChatGPT 身份。") }
        var error: Unmanaged<CFError>?
        let ok = SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, Data(signing.utf8) as CFData, signatureData as CFData, &error)
        if !ok { throw RecorderError.message("ChatGPT 身份签名无效。") }
    }

    private static func rsaKey(modulus: Data, exponent: Data) -> SecKey? {
        func prefix(_ data: Data) -> Data {
            var body = data
            if body.first == 0x00 { } else if (body.first ?? 0) >= 0x80 { body.insert(0x00, at: 0) }
            return Data([0x02]) + derLength(body.count) + body
        }
        let body = prefix(modulus) + prefix(exponent)
        let sequence = Data([0x30]) + derLength(body.count) + body
        let algorithm = Data([0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00])
        let bitString = Data([0x03]) + derLength(sequence.count + 1) + Data([0x00]) + sequence
        let wrapped = algorithm + bitString
        let spki = Data([0x30]) + derLength(wrapped.count) + wrapped
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        return SecKeyCreateWithData(spki as CFData, attributes as CFDictionary, nil)
    }

    private static func derLength(_ count: Int) -> Data {
        if count < 128 { return Data([UInt8(count)]) }
        var value = count
        var bytes: [UInt8] = []
        while value > 0 { bytes.insert(UInt8(value & 0xff), at: 0); value >>= 8 }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}

enum ChatGPTClient {
    static func complete(instructions: String, input: String, onProgress: ((Double) -> Void)? = nil) async throws -> String {
        guard ChatGPTAccount.canUsePlan else { throw RecorderError.message("请先在设置中登录 ChatGPT，并允许使用套餐。") }
        let token = try await ChatGPTAccount.accessToken()
        let model = try await modelSlug(token: token)
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["model": model, "instructions": instructions, "input": [["role": "user", "content": input]], "store": false, "stream": true]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RecorderError.message("ChatGPT 请求失败。")
        }
        var collected = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let type = json["type"] as? String ?? ""
            if type == "response.output_text.delta", let delta = json["delta"] as? String {
                collected += delta
                onProgress?(min(0.98, Double(collected.count) / 800))
            } else if type == "response.failed" {
                throw RecorderError.message("ChatGPT 套餐暂时无法完成这次请求。")
            } else if type == "response.completed" {
                onProgress?(1)
            }
        }
        let text = collected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw RecorderError.message("ChatGPT 没有返回内容。") }
        return text
    }

    private static func modelSlug(token: String) async throws -> String {
        if let saved = UserDefaults.standard.string(forKey: "chatgpt.model"), !saved.isEmpty { return saved }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RecorderError.message("无法读取 ChatGPT 可用模型。")
        }
        let models = (json["models"] as? [[String: Any]]) ?? (json["data"] as? [[String: Any]]) ?? []
        let slug = models.first {
            ($0["visibility"] as? String) == "list" || $0["visibility"] == nil
        }.flatMap { ($0["slug"] as? String) ?? ($0["id"] as? String) }
        guard let slug, !slug.isEmpty else { throw RecorderError.message("这个 ChatGPT 账号没有可用模型。") }
        UserDefaults.standard.set(slug, forKey: "chatgpt.model")
        return slug
    }
}

enum MeetingAI {
    static func summarize(transcript: String, onProgress: @escaping (Double) -> Void) async throws -> String {
        guard ChatGPTAccount.canUsePlan else { return try await DeepSeekClient.summarize(transcript: transcript, onProgress: onProgress) }
        let instructions = "你是会议记录助手。第一行必须是「主题：」加不超过16个字的内容主题。然后用中文整理结论、待办和关键发言。不要编造。以下是用户的长期记忆，必须遵守：\n\(MeetingMemory.text.isEmpty ? "（暂无）" : MeetingMemory.text)"
        return try await ChatGPTClient.complete(instructions: instructions, input: String(transcript.prefix(24_000)), onProgress: onProgress)
    }

    static func ask(question: String, recordings: [Recording]) async throws -> (answer: String, sources: [UUID]) {
        guard ChatGPTAccount.canUsePlan else { return try await DeepSeekClient.ask(question: question, recordings: recordings) }
        guard !recordings.isEmpty else { throw RecorderError.message("还没有录音可以提问。") }
        let corpus = recordings.prefix(20).map { item in
            let date = item.createdAt.formatted(date: .numeric, time: .shortened)
            return "[\(item.id.uuidString)] \(date) 时长\(Int(item.duration))秒 字数\(item.transcript.count) 标题：\(item.title)\n总结：\(item.summary.prefix(400))\n转写：\(item.transcript.prefix(2_000))"
        }.joined(separator: "\n\n")
        let instructions = "你是会议资料助手。先理解问题，再根据每条录音的日期、时长、字数、标题、总结和转写作统计或查找。先写答案，最后一行以「引用：」开头列出用到的 UUID，逗号分隔。已知记忆：\(MeetingMemory.text)"
        let content = try await ChatGPTClient.complete(instructions: instructions, input: "问题：\(question)\n\n\(corpus.prefix(24_000))")
        var answer = content
        var sources: [UUID] = []
        if let range = content.range(of: "引用：") {
            answer = String(content[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            sources = content[range.upperBound...].split(separator: ",").compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        return (answer.isEmpty ? content : answer, sources)
    }
}

struct ChatGPTSettingsView: View {
    @State private var email = ChatGPTAccount.email
    @State private var working = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                if email.isEmpty {
                    Button(working ? "正在打开登录…" : "Continue with ChatGPT") { connect() }.disabled(working)
                } else {
                    Text(email)
                    Button("退出登录", role: .destructive) { ChatGPTAccount.signOut(); email = "" }
                }
            } footer: {
                Text("登录后，会议总结和首页提问使用这个 ChatGPT 套餐。实时转写仍用 Apple 或阿里云。")
            }
        }
        .navigationTitle("ChatGPT")
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func connect() {
        working = true
        Task {
            defer { working = false }
            do { try await ChatGPTAccount.signIn(); email = ChatGPTAccount.email }
            catch { message = error.localizedDescription }
        }
    }
}

private enum LoopbackCallback {
    static func wait(port: UInt16, open url: URL) async throws -> [String: String] {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        return try await withCheckedThrowingContinuation { continuation in
            final class Once: @unchecked Sendable { var resumed = false; let lock = NSLock()
                func finish(_ result: Result<[String: String], Error>, _ continuation: CheckedContinuation<[String: String], Error>) {
                    lock.lock(); defer { lock.unlock() }
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(with: result)
                }
            }
            let once = Once()
            listener.newConnectionHandler = { connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let page = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n<p>可以回到 AikinRec。</p>"
                    connection.send(content: Data(page.utf8), completion: .contentProcessed { _ in connection.cancel() })
                    var values: [String: String] = [:]
                    if let query = text.split(separator: "\r\n").first?.split(separator: " ").dropFirst().first,
                       let components = URLComponents(string: "http://127.0.0.1" + query) {
                        for item in components.queryItems ?? [] { values[item.name] = item.value ?? "" }
                    }
                    listener.cancel()
                    once.finish(.success(values), continuation)
                }
            }
            listener.stateUpdateHandler = { state in
                if case .ready = state { DispatchQueue.main.async { UIApplication.shared.open(url) } }
                if case .failed(let error) = state { once.finish(.failure(error), continuation) }
            }
            listener.start(queue: .global())
        }
    }
}

private extension String {
    var urlQuery: String { addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self }
}

private extension Data {
    func base64URL() -> String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL text: String) {
        var value = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        self.init(base64Encoded: value)
    }
}
