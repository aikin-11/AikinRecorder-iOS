import SwiftUI

struct TrashView: View {
    @Environment(LibraryStore.self) private var store
    @State private var message: String?

    var body: some View {
        Group {
            if store.trash.isEmpty {
                ContentUnavailableView("回收站是空的", systemImage: "trash", description: Text("主页删除的录音、转写和总结会先放在这里。"))
            } else {
                List(store.trash) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.recording.title).lineLimit(2)
                        Text(item.deletedAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                        if !item.recording.transcript.isEmpty {
                            Text("含转写 \(Recording.countText(item.recording.transcript.count))字")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("恢复") { restore(item) }
                            Button("彻底删除", role: .destructive) { store.deleteTrash(item) }
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("回收站")
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func restore(_ item: TrashedRecording) {
        do { try store.restoreTrash(item) } catch { message = error.localizedDescription }
    }
}

struct TodoPickView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let recordingID: UUID
    let titles: [String]
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if titles.isEmpty {
                    ContentUnavailableView("没有找到待办", systemImage: "checklist", description: Text("总结里没有可提取的待办条目。"))
                } else {
                    List(titles, id: \.self) { title in
                        Button {
                            if selected.contains(title) { selected.remove(title) } else { selected.insert(title) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(title) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(title) ? Color.yellow : Color.secondary)
                                Text(title).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            }
                        }
                    }
                }
            }
            .navigationTitle("提取待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.count == titles.count && !titles.isEmpty ? "取消全选" : "全选") {
                        if selected.count == titles.count { selected.removeAll() } else { selected = Set(titles) }
                    }
                    .disabled(titles.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("加入待办") {
                        store.addTodos(Array(selected), recordingID: recordingID)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { selected = Set(titles) }
    }
}
