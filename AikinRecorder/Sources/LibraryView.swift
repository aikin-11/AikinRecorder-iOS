import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @State private var query = ""
    @State private var engine: AnswerEngine = .local
    @State private var asking = false
    @State private var askProgress = 0.0
    @State private var answer = ""
    @State private var answerSources: [Recording] = []
    @State private var showingAnswer = false
    @State private var showingRecorder = false
    @State private var showingSettings = false
    @State private var importing = false
    @State private var errorMessage: String?
    @State private var itemToDelete: Recording?
    @State private var deleteAnchor = CGPoint(x: 180, y: 320)
    @State private var showingTodos = false
    @State private var selectedItem: Recording?

    private var items: [Recording] {
        if engine != .local { return store.recordings }
        return store.recordings.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.transcript.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        statCard("录音", value: "\(store.recordings.count) 条")
                        statCard("转写字数", value: Recording.countText(store.recordings.reduce(0) { $0 + $1.transcript.count }))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    if items.isEmpty {
                    VStack(spacing: 10) {
                        Text(query.isEmpty ? "还没有录音" : "没有找到文件").font(.headline)
                        Text(query.isEmpty ? "录制一场会议，或从文件导入音频。" : "试试其他关键词。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding()
                } else {
                    List {
                        ForEach(items) { item in
                            LongPressDeleteRow(onDelete: { point in deleteAnchor = point; itemToDelete = item }, onOpen: { selectedItem = item }) {
                                RecordingRow(item: item, query: query, transcribing: store.transcribingID == item.id, queued: store.queuedIDs.contains(item.id))
                            }
                            .listRowBackground(Color.black)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    }
                }
            }
            .toolbar(selectedItem == nil ? .hidden : .visible, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Text("AikinRec")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("设置")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.black)
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Button { engine = engine.next } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "magnifyingglass")
                                if engine != .local { Text(engine.title).font(.caption.weight(.semibold)) }
                            }
                            .foregroundStyle(engine.tint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(engine.title)
                        TextField(engine == .local ? "输入标题或内容" : "输入内容", text: $query)
                            .textInputAutocapitalization(.never)
                            .onSubmit { if engine != .local { ask() } }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .glassEffect(.regular, in: .capsule)
                    Button { showingTodos = true } label: {
                        Image(systemName: "checklist")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("待办")
                    Menu {
                        Button("录音实时转写", systemImage: "mic") { showingRecorder = true }
                        Button("导入外部音频", systemImage: "square.and.arrow.down") { importAudio() }
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .disabled(importing)
                    .accessibilityLabel("新建")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(Color.black)
            }
            .navigationDestination(item: $selectedItem) { item in RecordingDetailView(item: item, initialQuery: query) }
            .sheet(isPresented: $showingRecorder) { RecorderView() }
            .overlay { if importing { ProgressView("正在导入…").padding(24).glassEffect(in: .rect(cornerRadius: 20)) } }
            .overlay {
                GeometryReader { geo in
                    if let item = itemToDelete {
                        let frame = geo.frame(in: .global)
                        let x = min(max(deleteAnchor.x - frame.minX, 120), max(120, geo.size.width - 120))
                        let y = min(max(deleteAnchor.y - frame.minY, 70), max(70, geo.size.height - 90))
                        Color.black.opacity(0.28)
                            .ignoresSafeArea()
                            .onTapGesture { itemToDelete = nil }
                        VStack(alignment: .leading, spacing: 12) {
                            Text("确定要删除吗？").font(.headline)
                            Button("删除录音", role: .destructive) {
                                do { try store.remove(item) } catch { errorMessage = error.localizedDescription }
                                itemToDelete = nil
                            }
                            Button("取消", role: .cancel) { itemToDelete = nil }
                        }
                        .padding(16)
                        .frame(width: 220, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .position(x: x, y: y)
                    }
                }
            }
            .sheet(isPresented: $showingTodos) { TodoListView() }
            .sheet(isPresented: $showingAnswer) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if asking {
                                ProgressView(value: askProgress) {
                                    Text("正在询问 \(engine.title)…")
                                }
                            }
                            if !answer.isEmpty {
                                MarkdownSummary(text: answer)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if !answerSources.isEmpty {
                                Text("引用").font(.headline)
                                ForEach(answerSources) { source in
                                    Button { showingAnswer = false; selectedItem = source } label: {
                                        Text(source.title)
                                            .underline()
                                            .foregroundStyle(.yellow)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding()
                    }
                    .navigationTitle("回答")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showingAnswer = false } } }
                }
                .preferredColorScheme(.dark)
            }
            .alert("提示", isPresented: Binding(get: { errorMessage != nil || store.errorMessage != nil }, set: { if !$0 { errorMessage = nil; store.errorMessage = nil } })) {
                Button("好") { errorMessage = nil; store.errorMessage = nil }
            } message: { Text(errorMessage ?? store.errorMessage ?? "") }
        }
    }

    private func ask() {
        let question = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard engine != .local, !question.isEmpty else { return }
        asking = true
        askProgress = 0
        answer = ""
        answerSources = []
        query = ""
        showingAnswer = true
        let recordings = store.recordings
        Task {
            defer { asking = false }
            do {
                let result = try await MeetingAI.ask(question: question, recordings: recordings, engine: engine) { value in
                    Task { @MainActor in askProgress = value }
                }
                answer = result.answer
                let ids = Set(result.sources)
                answerSources = recordings.filter { ids.contains($0.id) }
            } catch { errorMessage = error.localizedDescription; showingAnswer = false }
        }
    }

    private func statCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
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

}

private struct LongPressDeleteRow<Content: View>: View {
    let onDelete: (CGPoint) -> Void
    let onOpen: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var suppressTap = false
    @State private var anchor = CGPoint(x: 180, y: 320)

    var body: some View {
        Button {
            if suppressTap { suppressTap = false; return }
            onOpen()
        } label: { content() }
            .buttonStyle(.plain)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.frame(in: .global), initial: true) { _, frame in
                            anchor = CGPoint(x: frame.midX, y: frame.minY + 28)
                        }
                }
            }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                suppressTap = true
                onDelete(anchor)
            })
    }
}

private struct TodoListView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.todos.isEmpty {
                    ContentUnavailableView("还没有待办", systemImage: "checklist", description: Text("会议总结里的待办会出现在这里。"))
                } else {
                    List {
                        ForEach(store.todos) { item in
                            TodoRow(item: item)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct TodoRow: View {
    @Environment(LibraryStore.self) private var store
    let item: TodoItem
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                var next = item
                next.done.toggle()
                store.updateTodo(next)
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.done ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            Button { draft = item.title; editing = true } label: {
                Text(item.title)
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        }
        .alert("编辑待办", isPresented: $editing) {
            TextField("待办", text: $draft)
            Button("保存") {
                var next = item
                let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return }
                next.title = title
                store.updateTodo(next)
            }
            Button("取消", role: .cancel) { }
        }
    }
}

private struct RecordingRow: View {
    let item: Recording
    var query = ""
    var transcribing = false
    var queued = false
    var body: some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 7) {
                Text(item.title).font(.body.weight(.medium)).lineLimit(2).multilineTextAlignment(.leading)
                if !query.isEmpty, let snippet = highlightedSnippet(item.transcript, query: query) {
                    Text(snippet).font(.caption).lineLimit(2)
                }
                HStack {
                    Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                    Text("·")
                    Text(Recording.timeText(item.duration)).monospacedDigit()
                    if item.hasSummary { Text("· AI处理完毕 · \(Recording.countText(item.transcript.count))字") }
                    else if queued {
                        Text("· 排队中").foregroundStyle(.yellow)
                    } else if !item.transcript.isEmpty {
                        Text("· 已转写 \(Recording.countText(item.transcript.count))字")
                            .foregroundStyle(transcribing ? Color.yellow : Color.secondary)
                    } else if transcribing {
                        Text("· 正在转写").foregroundStyle(.yellow)
                    }
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
