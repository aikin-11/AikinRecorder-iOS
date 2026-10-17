import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = DeepSeekSettings.apiKey

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("DeepSeek")
                } footer: {
                    Text("会议总结会把转写文字发送到 api.deepseek.com。密钥只保存在这台手机。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        DeepSeekSettings.apiKey = apiKey
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
