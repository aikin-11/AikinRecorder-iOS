import SwiftUI
import UIKit
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
                            SwipeDeleteRow(onDelete: { itemToDelete = item }, onOpen: { selectedItem = item }) {
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
                        Button { askMode.toggle() } label: {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(askMode ? Color.yellow : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(askMode ? "关闭 DeepSeek 提问" : "用 DeepSeek 提问")
                        TextField(askMode ? "向 DeepSeek 提问" : "输入标题或内容", text: $query)
                            .textInputAutocapitalization(.never)
                            .onSubmit { if askMode { askDeepSeek() } }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .glassEffect(.regular, in: .capsule)
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
            .confirmationDialog("确定要删除吗？", isPresented: Binding(get: { itemToDelete != nil }, set: { if !$0 { itemToDelete = nil } }), titleVisibility: .visible) {
                Button("删除录音", role: .destructive) {
                    if let item = itemToDelete { do { try store.remove(item) } catch { errorMessage = error.localizedDescription } }
                    itemToDelete = nil
                }
            }
            .sheet(isPresented: $showingAnswer) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if asking { ProgressView("正在询问 DeepSeek…") }
                            Text(answer.isEmpty ? "还没有答案。" : answer)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                            if !answerSources.isEmpty {
                                Text("引用").font(.headline)
                                ForEach(answerSources) { source in
                                    Button(source.title) { showingAnswer = false; selectedItem = source }
                                        .frame(maxWidth: .infinity, alignment: .leading)
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
                let result = try await DeepSeekClient.ask(question: question, recordings: recordings)
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

private struct SwipeDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    let onOpen: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var offset: CGFloat = 0
    @State private var base: CGFloat = 0

    var body: some View {
        let reveal = max(0, -offset)
        HStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(
                    HorizontalRowGesture(base: base, onReveal: {
                        base = -96
                        withAnimation(.snappy) { offset = -96 }
                    }) { _ in
                    } onEnd: { _ in
                    } onTap: { x, width in
                        if base < -8, x > width - 100 {
                            onDelete()
                            return
                        }
                        if base < -8 {
                            base = 0
                            withAnimation(.snappy) { offset = 0 }
                        } else {
                            onOpen()
                        }
                    }
                )
            Color.clear
                .frame(width: reveal)
                .overlay(alignment: .trailing) {
                    Button(action: onDelete) {
                        Text("删除")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(maxHeight: .infinity)
                            .frame(width: 72)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .clipped()
        }
        .clipped()
    }
}

private struct HorizontalRowGesture: UIViewRepresentable {
    var base: CGFloat
    var onReveal: () -> Void
    var onChange: (CGFloat) -> Void
    var onEnd: (CGFloat) -> Void
    var onTap: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(base: base, onReveal: onReveal, onChange: onChange, onEnd: onEnd, onTap: onTap) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.press(_:)))
        press.minimumPressDuration = 0.45
        press.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(press)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.base = base
        context.coordinator.onReveal = onReveal
        context.coordinator.onChange = onChange
        context.coordinator.onEnd = onEnd
        context.coordinator.onTap = onTap
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var base: CGFloat
        var onChange: (CGFloat) -> Void
        var onEnd: (CGFloat) -> Void
        var onTap: (CGFloat, CGFloat) -> Void
        var onReveal: () -> Void

        init(base: CGFloat, onReveal: @escaping () -> Void, onChange: @escaping (CGFloat) -> Void, onEnd: @escaping (CGFloat) -> Void, onTap: @escaping (CGFloat, CGFloat) -> Void) {
            self.base = base
            self.onReveal = onReveal
            self.onChange = onChange
            self.onEnd = onEnd
            self.onTap = onTap
        }

        @objc func press(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            onReveal()
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view else { return }
            onTap(gesture.location(in: view).x, view.bounds.width)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
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
                    if !item.summary.isEmpty { Text("· AI处理完毕 · \(Recording.countText(item.transcript.count))字") }
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
