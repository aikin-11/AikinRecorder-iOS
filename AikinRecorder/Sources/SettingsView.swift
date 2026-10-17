import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var usage: Int64 = 0
    @State private var selected: Set<UUID> = []
    @State private var message: String?
    @State private var confirmingCleanup = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink("DeepSeek") { DeepSeekSettingsView() }
                    NavigationLink("阿里云百炼") { BailianSettingsView() }
                } header: { Text("模型服务") } footer: {
                    Text("点进去填写密钥。密钥只保存在这台手机。")
                }
                Section {
                    NavigationLink("我的记忆") { MeetingMemoryView() }
                } footer: {
                    Text("告诉 DeepSeek 你是谁、会议在做什么。它会记住，也可以改正。")
                }
                Section {
                    NavigationLink {
                        List {
                            ForEach(store.recordings) { item in
                                Toggle(isOn: Binding(get: { selected.contains(item.id) }, set: { on in
                                    if on { selected.insert(item.id) } else { selected.remove(item.id) }
                                })) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title).lineLimit(1)
                                        Text(ByteCountFormatter.string(fromByteCount: store.fileBytes(item), countStyle: .file))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .tint(.green)
                            }
                            Button("清理所选录音", role: .destructive) { confirmingCleanup = true }
                                .disabled(selected.isEmpty)
                        }
                        .navigationTitle("录音空间")
                    } label: {
                        LabeledContent("已用空间", value: ByteCountFormatter.string(fromByteCount: usage, countStyle: .file))
                    }
                } header: { Text("录音空间") } footer: {
                    Text("点进去查看每条录音的大小。清理会删除所选录音、转写和总结，且不能恢复。")
                }
                Section {
                    NavigationLink("WebDAV") { WebDAVSettingsView() }
                } header: { Text("备份") } footer: {
                    Text("点进去填写服务器、账号和保存位置。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
            .onAppear { usage = store.storageBytes() }
            .confirmationDialog("删除所选录音？", isPresented: $confirmingCleanup, titleVisibility: .visible) {
                Button("清理", role: .destructive) { cleanup() }
            }
            .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好") { message = nil }
            } message: { Text(message ?? "") }
        }
        .preferredColorScheme(.dark)
    }

    private func cleanup() {
        do {
            for item in store.recordings where selected.contains(item.id) { try store.remove(item) }
            selected.removeAll()
            usage = store.storageBytes()
        } catch { message = error.localizedDescription }
    }
}

private struct WebDAVSettingsView: View {
    @Environment(LibraryStore.self) private var store
    @State private var webURL = WebDAVSettings.url
    @State private var webUser = WebDAVSettings.username
    @State private var webPassword = WebDAVSettings.password
    @State private var webPath = WebDAVSettings.remotePath
    @State private var syncEnabled = WebDAVSettings.syncMinute >= 0
    @State private var syncTime = Self.date(minute: max(0, WebDAVSettings.syncMinute))
    @State private var message: String?
    @State private var working = false

    var body: some View {
        Form {
            Section {
                TextField("服务器地址", text: $webURL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("账号", text: $webUser).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("密码", text: $webPassword)
                TextField("保存位置", text: $webPath).textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("每天定时同步", isOn: $syncEnabled).tint(.green)
                if syncEnabled {
                    DatePicker("同步时间", selection: $syncTime, displayedComponents: .hourAndMinute)
                }
                Button(working ? "正在连接…" : "测试连接") { testConnection() }.disabled(working)
                Button("立即同步") { syncNow() }.disabled(working)
                NavigationLink("已备份") { BackupListView() }
            } footer: {
                Text("先测试服务器本身是否连通。这台 NAS 的根目录不能新建文件夹，保存位置请填 /存储空间1/AikinRecorder。")
            }
        }
        .navigationTitle("WebDAV")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { save() }
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }

    private static func date(minute: Int) -> Date {
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        parts.hour = minute / 60
        parts.minute = minute % 60
        return Calendar.current.date(from: parts) ?? .now
    }

    private func save() {
        WebDAVSettings.url = webURL
        WebDAVSettings.username = webUser
        WebDAVSettings.password = webPassword
        WebDAVSettings.remotePath = webPath
        let parts = Calendar.current.dateComponents([.hour, .minute], from: syncTime)
        WebDAVSettings.syncMinute = syncEnabled ? (parts.hour ?? 0) * 60 + (parts.minute ?? 0) : -1
        WebDAVSettings.autoSync = syncEnabled
    }

    private func testConnection() {
        save()
        working = true
        Task {
            defer { working = false }
            do { try await WebDAVSync.test(); message = "WebDAV 连接成功。" }
            catch { message = error.localizedDescription }
        }
    }

    private func syncNow() {
        save()
        working = true
        Task {
            defer { working = false }
            do { try await WebDAVSync.sync(store); message = "同步完成。" }
            catch { message = error.localizedDescription }
        }
    }
}

private struct MeetingMemoryView: View {
    @State private var memory = MeetingMemory.text
    @State private var note = ""
    @State private var working = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Text(memory.isEmpty ? "还没有记忆。" : memory)
                    .font(.callout)
            } header: { Text("当前记忆") }
            Section {
                TextField("例如：我是 Aikin，周会讨论产品进度", text: $note, axis: .vertical)
                Button(working ? "正在整理…" : "发送给 DeepSeek") { send() }
                    .disabled(working || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: { Text("DeepSeek 会把这句话补进记忆，也可以纠正原来写错的内容。") }
        }
        .navigationTitle("我的记忆")
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func send() {
        let input = note
        working = true
        Task {
            defer { working = false }
            do {
                memory = try await DeepSeekClient.reviseMemory(input)
                MeetingMemory.text = memory
                note = ""
            } catch { message = error.localizedDescription }
        }
    }
}

private struct DeepSeekSettingsView: View {
    @State private var apiKey = DeepSeekSettings.apiKey
    @State private var message: String?
    @State private var working = false
    var body: some View {
        Form {
            Section {
                SecureField("API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(working ? "正在测试…" : "测试连接") { test() }.disabled(working)
                Button("保存") { save(); message = "已保存。" }
            } footer: {
                Text("会议总结会把转写文字发送到 api.deepseek.com。")
            }
        }
        .navigationTitle("DeepSeek")
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func save() { DeepSeekSettings.apiKey = apiKey }

    private func test() {
        save()
        working = true
        Task {
            defer { working = false }
            do { try await DeepSeekClient.test(); message = "DeepSeek 连接成功。" }
            catch { message = error.localizedDescription }
        }
    }
}

private struct BailianSettingsView: View {
    @State private var apiKey = BailianSettings.apiKey
    @State private var model = BailianSettings.model
    @State private var endpoint = BailianSettings.endpoint
    @State private var message: String?
    @State private var working = false
    var body: some View {
        Form {
            Section {
                SecureField("API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("模型", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("WebSocket 地址", text: $endpoint, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(working ? "正在测试…" : "测试连接") { test() }.disabled(working)
                Button("保存") { save(); message = "已保存。" }
            } footer: {
                Text("实时转写页可选「阿里云模型」。默认模型 qwen-audio-3.1-asr-flash-streaming，音频按 16 kHz PCM 发送。华北2（北京）地址为 wss://dashscope.aliyuncs.com/api-ws/v1/inference。")
            }
        }
        .navigationTitle("阿里云百炼")
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func save() {
        BailianSettings.apiKey = apiKey
        BailianSettings.model = model
        BailianSettings.endpoint = endpoint
    }

    private func test() {
        save()
        working = true
        Task {
            defer { working = false }
            do { try await BailianSettings.test(); message = "阿里云百炼连接成功。" }
            catch { message = error.localizedDescription }
        }
    }
}

private struct BackupListView: View {
    @State private var items: [WebDAVBackup] = []
    @State private var selected: Set<String> = []
    @State private var message: String?
    @State private var loading = false

    var body: some View {
        List {
            if loading && items.isEmpty { ProgressView("正在读取备份…") }
            ForEach(items) { item in
                Toggle(isOn: Binding(get: { selected.contains(item.path) }, set: { on in
                    if on { selected.insert(item.path) } else { selected.remove(item.path) }
                })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(.green)
            }
            Button("删除所选备份", role: .destructive) { remove() }
                .disabled(selected.isEmpty || loading)
        }
        .navigationTitle("已备份")
        .task { await reload() }
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        do { items = try await WebDAVSync.backups() }
        catch { message = error.localizedDescription }
    }

    private func remove() {
        let paths = Array(selected)
        loading = true
        Task {
            defer { loading = false }
            do {
                try await WebDAVSync.deleteBackups(paths)
                selected.removeAll()
                items = try await WebDAVSync.backups()
            } catch { message = error.localizedDescription }
        }
    }
}
