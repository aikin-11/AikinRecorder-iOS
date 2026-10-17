import SwiftUI

struct RecordingDetailView: View {
    @Environment(LibraryStore.self) private var store
    @State var item: Recording
    var initialQuery = ""
    @State private var player = PlaybackModel()
    @State private var errorMessage: String?
    @State private var showingRename = false
    @State private var titleDraft = ""
    @State private var summarizing = false
    @State private var summaryProgress = 0.0
    @State private var showingSummary = false
    @State private var suggestedTitle = ""
    @State private var offeringTitle = false
    @State private var titleReady = false
    @State private var findText = ""
    @State private var findIndex = 0
    @State private var showingFind = false
    @State private var showingMarks = false
    @State private var transcriptScrubbing = false
    @State private var confirmingRetranscribe = false

    var body: some View {
        @Bindable var player = player
        VStack(spacing: 16) {
            HStack {
                Text(item.createdAt, format: .dateTime.year().month().day().hour().minute())
                Spacer()
                Text("\(item.transcript.count) 字").monospacedDigit()
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            ScrollViewReader { proxy in
                ScrollView {
                    if item.lines.isEmpty {
                        Text(highlighted(item.transcript.isEmpty ? "暂无转写文字。" : item.transcript))
                            .foregroundStyle(item.transcript.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(20)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(item.lines) { line in
                                HStack(alignment: .top, spacing: 12) {
                                    HStack(spacing: 2) {
                                        Text(Recording.timeText(alignedTime(line)))
                                        if item.marks.contains(where: { abs($0.time - line.time) < 1.2 }) {
                                            Image(systemName: "bookmark.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                                        }
                                    }
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 78, alignment: .leading)
                                    Text(highlighted(line.text))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(activeLineID == line.id ? Color.white : Color.clear, lineWidth: 1.4))
                                        .contentShape(Rectangle())
                                        .highPriorityGesture(TapGesture().onEnded { player.play(from: alignedTime(line)) })
                                }
                                .id(line.id)
                            }
                        }
                        .padding(20)
                    }
                }
                .onChange(of: item.lines.count) {
                    if let id = item.lines.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
                .onChange(of: store.transcriptTick) {
                    guard store.transcribingID == item.id, let latest = store.recordings.first(where: { $0.id == item.id }) else { return }
                    item.lines = latest.lines
                    item.transcript = latest.transcript
                    if let id = item.lines.last?.id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
                .onChange(of: activeLineID) {
                    guard player.isPlaying, let id = activeLineID else { return }
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: player.position) {
                    guard transcriptScrubbing, let id = activeLineID else { return }
                    proxy.scrollTo(id, anchor: .center)
                }
                .onChange(of: findIndex) {
                    let hits = item.lines.filter { $0.text.localizedStandardContains(findText) }
                    if findText.isEmpty || hits.isEmpty { return }
                    proxy.scrollTo(hits[min(findIndex, hits.count - 1)].id, anchor: .center)
                }
            }
            HStack {
                Button(transcriptButtonTitle, systemImage: "text.bubble") { transcriptAction() }
                if store.transcribingID == item.id {
                    ProgressView(value: store.transcriptProgress)
                    Text("\(Int(store.transcriptProgress * 100))%").font(.caption.monospacedDigit())
                }
                Spacer()
            }
            .font(.subheadline)
            .padding(.horizontal)
            VStack(spacing: 8) {
                Slider(value: Binding(get: { player.position }, set: { player.scrub(to: $0) }), in: 0...max(0.01, player.duration), onEditingChanged: { editing in
                    transcriptScrubbing = editing
                    if editing { player.beginScrub() } else { player.endScrub() }
                })
                    .accessibilityLabel("播放进度")
                HStack { Text(Recording.timeText(player.position)); Spacer(); Text(Recording.timeText(player.duration)) }
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                GlassEffectContainer(spacing: 24) {
                    HStack(spacing: 36) {
                        Button { player.seek(player.position - 10) } label: { Image(systemName: "gobackward.10").font(.title2).frame(width: 44, height: 44) }.accessibilityLabel("后退十秒")
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                                .foregroundStyle(.black).frame(width: 68, height: 68).background(.white, in: Circle())
                        }.accessibilityLabel(player.isPlaying ? "暂停播放" : "播放录音")
                        Button { player.seek(player.position + 10) } label: { Image(systemName: "goforward.10").font(.title2).frame(width: 44, height: 44) }.accessibilityLabel("前进十秒")
                    }
                }.padding(.vertical, 10)
            }.padding(20).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24)).padding(.horizontal)
        }
        .padding(.bottom, 12).background(Color.black)
        .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("重命名", systemImage: "pencil") { titleDraft = item.title; showingRename = true }
                    Button("分享音频", systemImage: "waveform") { share(audio: true) }
                    Button("导出文字", systemImage: "doc.text") { share(audio: false) }.disabled(item.transcript.isEmpty)
                    Button(transcriptButtonTitle, systemImage: "text.bubble") { transcriptAction() }.disabled(store.transcribingID != nil && store.transcribingID != item.id)
                    Button("查找", systemImage: "magnifyingglass") { showingFind = true }
                    Button("标记说明", systemImage: "star") { showingMarks = true }.disabled(item.marks.isEmpty)
                    Button(item.summary.isEmpty ? "会议总结" : "查看总结", systemImage: "sparkles") { openSummary() }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("更多操作")
            }
        }
        .alert("重命名", isPresented: $showingRename) {
            TextField("录音名称", text: $titleDraft)
            Button("保存") { item.title = Recording.cleanTitle(titleDraft); save() }
            Button("取消", role: .cancel) { }
        }
        .alert("提示", isPresented: Binding(get: { errorMessage != nil || player.errorMessage != nil }, set: { if !$0 { errorMessage = nil; player.errorMessage = nil } })) {
            Button("好") { errorMessage = nil; player.errorMessage = nil }
        } message: { Text(errorMessage ?? player.errorMessage ?? "") }
        .sheet(isPresented: $showingFind) {
            NavigationStack {
                Form {
                    TextField("查找内容", text: $findText)
                    Button("上一处") { findIndex = max(0, findIndex - 1) }.disabled(findText.isEmpty)
                    Button("下一处") { findIndex += 1 }.disabled(findText.isEmpty)
                }
                .navigationTitle("查找")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingFind = false } } }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingMarks) {
            NavigationStack {
                Form {
                    ForEach($item.marks) { $mark in
                        Section(Recording.timeText(mark.time)) {
                            TextField("标记说明", text: $mark.note, axis: .vertical)
                            Button("跳到这里") { player.play(from: mark.time); showingMarks = false }
                        }
                    }
                }
                .navigationTitle("标记说明")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { save(); showingMarks = false } } }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingSummary, onDismiss: {
            if titleReady { titleReady = false; offeringTitle = true }
        }) {
            SummarySheet(summary: item.summary, progress: summaryProgress, working: summarizing) {
                do { SystemPresenter.share(try store.shareSummary(item)) }
                catch { errorMessage = error.localizedDescription }
            }
        }
        .onAppear { player.load(store.audioURL(for: item)); findText = initialQuery }
        .onChange(of: store.recordings.first { $0.id == item.id }?.transcript) {
            if store.transcribingID == item.id, let latest = store.recordings.first(where: { $0.id == item.id }) {
                item.lines = latest.lines
                item.transcript = latest.transcript
                item.transcribedThrough = latest.transcribedThrough
            }
        }
        .confirmationDialog("重新转写会替换现有文字", isPresented: $confirmingRetranscribe, titleVisibility: .visible) {
            Button("重新转写", role: .destructive) { startTranscription(replacing: true) }
        }
        .alert("用这个标题替换？", isPresented: $offeringTitle) {
            Button("替换") { item.title = Recording.cleanTitle(String(suggestedTitle.prefix(16))); save() }
            Button("保留原标题", role: .cancel) { }
        } message: { Text(suggestedTitle) }
        .onDisappear {
            player.stop()
            save()
        }
    }

    private var activeLineID: UUID? {
        let sorted = item.lines.sorted { alignedTime($0) < alignedTime($1) }
        return sorted.last { alignedTime($0) <= player.position + 0.2 }?.id ?? sorted.first?.id
    }

    private var storedTimesUsable: Bool {
        let duration = max(item.duration, player.duration)
        guard duration > 1, item.lines.count > 1 else { return item.lines.allSatisfy { $0.time >= 0 } }
        let times = item.lines.map(\.time).sorted()
        guard let first = times.first, let last = times.last else { return false }
        return first < duration * 0.2 && last > duration * 0.45 && last <= duration * 1.05 && last - first > duration * 0.35
    }

    private func alignedTime(_ line: TranscriptCue) -> TimeInterval {
        if storedTimesUsable { return line.time }
        let duration = max(item.duration, player.duration, 0.01)
        let total = max(1, item.lines.reduce(0) { $0 + $1.text.count })
        var before = 0
        for cue in item.lines {
            if cue.id == line.id { break }
            before += cue.text.count
        }
        return duration * Double(before) / Double(total)
    }

    private func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        let needle = findText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 1 else { return result }
        var search = result.startIndex
        while let range = result[search...].range(of: needle, options: .caseInsensitive) {
            result[range].backgroundColor = .yellow
            result[range].foregroundColor = .black
            search = range.upperBound
            if search >= result.endIndex { break }
        }
        return result
    }

    private func save() {
        do { try store.update(item) } catch { errorMessage = error.localizedDescription }
    }

    private func share(audio: Bool) {
        do {
            save()
            SystemPresenter.share(try audio ? store.shareAudio(item) : store.shareText(item))
        } catch { errorMessage = error.localizedDescription }
    }

    private func openSummary() {
        if item.summary.isEmpty { summarize() }
        else { showingSummary = true }
    }

    private func summarize() {
        summarizing = true
        summaryProgress = 0.15
        showingSummary = true
        let transcript = item.transcript
        Task {
            defer { summarizing = false }
            do {
                summaryProgress = 0.45
                item.summary = try await DeepSeekClient.summarize(transcript: transcript)
                summaryProgress = 1
                save()
                let theme = DeepSeekClient.theme(from: item.summary)
                if !theme.isEmpty, theme != item.title {
                    suggestedTitle = theme
                    titleReady = true
                }
            } catch {
                showingSummary = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private var transcriptButtonTitle: String {
        if store.transcribingID == item.id { return store.transcriptPaused ? "继续转写" : "暂停转写" }
        if item.transcribedThrough > 1, item.transcribedThrough + 1 < max(item.duration, player.duration) { return "继续转写" }
        return "转写文字"
    }

    private func transcriptAction() {
        if store.transcribingID == item.id {
            store.toggleTranscriptPause()
            return
        }
        let resume = item.transcribedThrough > 1 && item.transcribedThrough + 1 < max(item.duration, player.duration)
        if !resume && !item.transcript.isEmpty {
            confirmingRetranscribe = true
            return
        }
        startTranscription(replacing: !resume)
    }

    private func startTranscription(replacing: Bool) {
        player.pause()
        if replacing {
            item.lines = []
            item.transcript = ""
            item.transcribedThrough = 0
            save()
        }
        store.beginTranscription(item, from: replacing ? 0 : item.transcribedThrough)
    }
}

private struct SummarySheet: View {
    let summary: String
    let progress: Double
    let working: Bool
    let export: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if working {
                    ProgressView(value: progress) { Text("正在生成会议总结…").font(.footnote) }
                        .padding(.horizontal)
                }
                ScrollView {
                    MarkdownSummary(text: summary.isEmpty ? (working ? "正在整理…" : "还没有总结。") : summary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            .navigationTitle("会议总结")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = summary }
                        Button("导出 TXT", systemImage: "square.and.arrow.up") { export() }
                    } label: { Image(systemName: "ellipsis") }
                    .disabled(summary.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

}

private struct MarkdownSummary: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let line):
                    Text(inline(line)).font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline).textSelection(.enabled)
                case .paragraph(let line):
                    Text(inline(line)).font(.body).textSelection(.enabled)
                }
            }
        }
    }

    private enum Block { case heading(Int, String), paragraph(String) }

    private var blocks: [Block] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return nil }
            if line.hasPrefix("### ") { return .heading(3, String(line.dropFirst(4))) }
            if line.hasPrefix("## ") { return .heading(2, String(line.dropFirst(3))) }
            if line.hasPrefix("# ") { return .heading(1, String(line.dropFirst(2))) }
            return .paragraph(line)
        }
    }

    private func inline(_ source: String) -> AttributedString {
        var result = AttributedString()
        var rest = source
        while let start = rest.range(of: "**") {
            result += AttributedString(rest[..<start.lowerBound])
            rest = String(rest[start.upperBound...])
            guard let end = rest.range(of: "**") else { result += AttributedString("**" + rest); return result }
            var bold = AttributedString(rest[..<end.lowerBound])
            bold.font = .body.bold()
            result += bold
            rest = String(rest[end.upperBound...])
        }
        result += AttributedString(rest.replacingOccurrences(of: "*", with: ""))
        return result
    }
}
