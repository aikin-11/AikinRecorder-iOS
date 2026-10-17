import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @State private var query = ""
    @State private var showingRecorder = false
    @State private var showingSettings = false
    @State private var importing = false
    @State private var errorMessage: String?
    @State private var itemToDelete: Recording?
    @State private var selectedItem: Recording?

    private var items: [Recording] {
        store.recordings.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.transcript.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if items.isEmpty {
                    VStack(spacing: 10) {
                        Text(query.isEmpty ? "还没有录音" : "没有找到文件").font(.headline)
                        Text(query.isEmpty ? "录制一场会议，或从文件导入音频。" : "试试其他关键词。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding()
                } else {
                    List {
                        ForEach(items) { item in
                            Button { selectedItem = item } label: { RecordingRow(item: item, query: query) }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                .contextMenu {
                                    Button("打开", systemImage: "doc.text") { selectedItem = item }
                                    Button("删除", systemImage: "trash", role: .destructive) { itemToDelete = item }
                                }
                                .swipeActions { Button("删除", role: .destructive) { itemToDelete = item } }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("录音列表")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索转写内容")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("设置")
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .safeAreaInset(edge: .bottom) {
                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 12) {
                        action("录音实时转写", symbol: "mic") { showingRecorder = true }
                        action("导入外部音频", symbol: "square.and.arrow.down") { importAudio() }
                    }.padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .navigationDestination(item: $selectedItem) { item in RecordingDetailView(item: item, initialQuery: query) }
            .sheet(isPresented: $showingRecorder) { RecorderView() }
            .overlay { if importing { ProgressView("正在导入…").padding(24).glassEffect(in: .rect(cornerRadius: 20)) } }
            .confirmationDialog("删除这条录音及转写文字？", isPresented: Binding(get: { itemToDelete != nil }, set: { if !$0 { itemToDelete = nil } }), titleVisibility: .visible) {
                Button("删除录音", role: .destructive) {
                    if let item = itemToDelete { do { try store.remove(item) } catch { errorMessage = error.localizedDescription } }
                    itemToDelete = nil
                }
            }
            .alert("提示", isPresented: Binding(get: { errorMessage != nil || store.errorMessage != nil }, set: { if !$0 { errorMessage = nil; store.errorMessage = nil } })) {
                Button("好") { errorMessage = nil; store.errorMessage = nil }
            } message: { Text(errorMessage ?? store.errorMessage ?? "") }
        }
    }

    private func importAudio() {
        SystemPresenter.pickAudio { urls in
            Task {
                importing = true
                defer { importing = false }
                for url in urls {
                    do { _ = try await store.importAudio(from: url) }
                    catch { errorMessage = "\(url.lastPathComponent)：\(error.localizedDescription)" }
                }
            }
        }
    }

    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.horizontal, 16)
                .foregroundStyle(.white)
                .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.65), lineWidth: 0.7).allowsHitTesting(false))
        .disabled(importing)
    }
}

private struct RecordingRow: View {
    let item: Recording
    var query = ""
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "play.fill").font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40).background(.white.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 7) {
                Text(item.title).font(.title3.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                if !query.isEmpty, let snippet = highlightedSnippet(item.transcript, query: query) {
                    Text(snippet).font(.caption).lineLimit(2)
                }
                HStack {
                    Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                    Text("·")
                    Text(Recording.timeText(item.duration)).monospacedDigit()
                    if !item.summary.isEmpty { Text("· AI处理完毕") }
                    else if !item.transcript.isEmpty { Text("· 已转写") }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.35), lineWidth: 0.7))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private func highlightedSnippet(_ text: String, query: String) -> AttributedString? {
        guard let range = text.range(of: query, options: .caseInsensitive) else { return nil }
        let start = text.index(range.lowerBound, offsetBy: -24, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 24, limitedBy: text.endIndex) ?? text.endIndex
        var snippet = AttributedString(String(text[start..<end]))
        if let hit = snippet.range(of: query, options: .caseInsensitive) {
            snippet[hit].backgroundColor = .yellow
            snippet[hit].foregroundColor = .black
        }
        return snippet
    }
}
