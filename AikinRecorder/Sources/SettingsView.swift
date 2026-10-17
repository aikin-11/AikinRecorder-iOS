import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = DeepSeekSettings.apiKey
    @State private var webURL = WebDAVSettings.url
    @State private var webUser = WebDAVSettings.username
    @State private var webPassword = WebDAVSettings.password
    @State private var webPath = WebDAVSettings.remotePath
    @State private var intervalHours = WebDAVSettings.intervalHours
    @State private var usage: Int64 = 0
    @State private var selected: Set<UUID> = []
    @State private var message: String?
    @State private var confirmingCleanup = false
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: { Text("DeepSeek") } footer: {
                    Text("会议总结会把转写文字发送到 api.deepseek.com。密钥只保存在这台手机。")
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
                } header: { Text("WebDAV") } footer: {
                    Text("先测试服务器本身是否连通。这台 NAS 的根目录不能新建文件夹，保存位置请填 /存储空间1/AikinRecorder。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save(); dismiss() } }
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

    private func save() {
        DeepSeekSettings.apiKey = apiKey
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

    private func cleanup() {
        do {
            for item in store.recordings where selected.contains(item.id) { try store.remove(item) }
            selected.removeAll()
            usage = store.storageBytes()
        } catch { message = error.localizedDescription }
    }
}
