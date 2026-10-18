import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @State private var query = ""
    @State private var askMode = false
    @State private var asking = false
    @State private var answer = ""
    @State private var answerSources: [Recording] = []
    @State private var showingAnswer = false
    @State private var showingRecorder = false
    @State private var showingSettings = false
    @State private var importing = false
    @State private var errorMessage: String?
    @State private var itemToDelete: Recording?
    @State private var selectedItem: Recording?

    private var items: [Recording] {
        if askMode { return store.recordings }
        return store.recordings.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.transcript.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        statCard("褰曢煶", value: "\(store.recordings.count) 鏉?)
                        statCard("杞啓瀛楁暟", value: Recording.countText(store.recordings.reduce(0) { $0 + $1.transcript.count }))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    if items.isEmpty {
                    VStack(spacing: 10) {
                        Text(query.isEmpty ? "杩樻病鏈夊綍闊? : "娌℃湁鎵惧埌鏂囦欢").font(.headline)
                        Text(query.isEmpty ? "褰曞埗涓€鍦轰細璁紝鎴栦粠鏂囦欢瀵煎叆闊抽銆? : "璇曡瘯鍏朵粬鍏抽敭璇嶃€?)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding()
                } else {
                    List {
                        ForEach(items) { item in
                            LongPressDeleteRow(onDelete: { itemToDelete = item }, onOpen: { selectedItem = item }) {
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
            .toolbar(.hidden, for: .navigationBar)
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
                    .accessibilityLabel("璁剧疆")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.black)
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Button { askMode.toggle() } label: {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(askMode ? Color.yellow : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(askMode ? "鍏抽棴 DeepSeek 鎻愰棶" : "鐢?DeepSeek 鎻愰棶")
                        TextField(askMode ? "鍚?DeepSeek 鎻愰棶" : "杈撳叆鏍囬鎴栧唴瀹?, text: $query)
                            .textInputAutocapitalization(.never)
                            .onSubmit { if askMode { askDeepSeek() } }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .glassEffect(.regular, in: .capsule)
                    Menu {
                        Button("褰曢煶瀹炴椂杞啓", systemImage: "mic") { showingRecorder = true }
                        Button("瀵煎叆澶栭儴闊抽", systemImage: "square.and.arrow.down") { importAudio() }
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .disabled(importing)
                    .accessibilityLabel("鏂板缓")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(Color.black)
            }
            .navigationDestination(item: $selectedItem) { item in RecordingDetailView(item: item, initialQuery: query) }
            .sheet(isPresented: $showingRecorder) { RecorderView() }
            .overlay { if importing { ProgressView("姝ｅ湪瀵煎叆鈥?).padding(24).glassEffect(in: .rect(cornerRadius: 20)) } }
            .confirmationDialog("纭畾瑕佸垹闄ゅ悧锛?, isPresented: Binding(get: { itemToDelete != nil }, set: { if !$0 { itemToDelete = nil } }), titleVisibility: .visible) {
                Button("鍒犻櫎褰曢煶", role: .destructive) {
                    if let item = itemToDelete { do { try store.remove(item) } catch { errorMessage = error.localizedDescription } }
                    itemToDelete = nil
                }
            }
            .sheet(isPresented: $showingAnswer) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if asking { ProgressView(ChatGPTAccount.canUsePlan ? "姝ｅ湪璇㈤棶 ChatGPT鈥? : "姝ｅ湪璇㈤棶 DeepSeek鈥?) }
                            Text(answer.isEmpty ? "杩樻病鏈夌瓟妗堛€? : answer)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                            if !answerSources.isEmpty {
                                Text("寮曠敤").font(.headline)
                                ForEach(answerSources) { source in
                                    Button(source.title) { showingAnswer = false; selectedItem = source }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding()
                    }
                    .navigationTitle("鍥炵瓟")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("鍏抽棴") { showingAnswer = false } } }
                }
                .preferredColorScheme(.dark)
            }
            .alert("鎻愮ず", isPresented: Binding(get: { errorMessage != nil || store.errorMessage != nil }, set: { if !$0 { errorMessage = nil; store.errorMessage = nil } })) {
                Button("濂?) { errorMessage = nil; store.errorMessage = nil }
            } message: { Text(errorMessage ?? store.errorMessage ?? "") }
        }
    }

    private func askDeepSeek() {
        let question = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        asking = true
        answer = ""
        answerSources = []
        showingAnswer = true
        let recordings = store.recordings
        Task {
            defer { asking = false }
            do {
                let result = try await MeetingAI.ask(question: question, recordings: recordings)
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
                    catch { errorMessage = "\(url.lastPathComponent)锛歕(error.localizedDescription)" }
                }
            }
        }
    }

}

private struct LongPressDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    let onOpen: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var suppressTap = false

    var body: some View {
        Button {
            if suppressTap { suppressTap = false; return }
            onOpen()
        } label: { content() }
            .buttonStyle(.plain)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                suppressTap = true
                onDelete()
            })
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
                    Text("路")
                    Text(Recording.timeText(item.duration)).monospacedDigit()
                    if !item.summary.isEmpty { Text("路 AI澶勭悊瀹屾瘯 路 \(Recording.countText(item.transcript.count))瀛?) }
                    else if queued {
                        Text("路 鎺掗槦涓?).foregroundStyle(.yellow)
                    } else if !item.transcript.isEmpty {
                        Text("路 宸茶浆鍐?\(Recording.countText(item.transcript.count))瀛?)
                            .foregroundStyle(transcribing ? Color.yellow : Color.secondary)
                    } else if transcribing {
                        Text("路 姝ｅ湪杞啓").foregroundStyle(.yellow)
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
