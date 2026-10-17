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
    @State private var intervalHours = WebDAVSettings.intervalHours
    @State private var message: String?
    @State private var working = false

    var body: some View {
        Form {
            Section {
                TextField("服务器地址", text: $webURL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("账号", text: $webUser).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("密码", text: $webPassword)
                TextField("保存位置", text: $webPath).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("自动同步", selection: $intervalHours) {
                    Text("关闭").tag(0)
                    Text("每 6 小时").tag(6)
                    Text("每 24 小时").tag(24)
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

    private func save() {
        WebDAVSettings.url = webURL
        WebDAVSettings.username = webUser
        WebDAVSettings.password = webPassword
        WebDAVSettings.remotePath = webPath
        WebDAVSettings.intervalHours = intervalHours
        WebDAVSettings.autoSync = intervalHours > 0
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
                Text("实时转写页可选「阿里云百炼」。默认模型 qwen-audio-asr-flash，音频按 16 kHz PCM 发送。华北2（北京）地址为 wss://dashscope.aliyuncs.com/api-ws/v1/inference。")
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
