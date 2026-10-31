import SwiftUI

struct RecordingDetailView: View {
    @Environment(LibraryStore.self) private var store
    @State var item: Recording
    var initialQuery = ""
    var opensTranscript = false
    @State private var player = PlaybackModel()
    @State private var errorMessage: String?
    @State private var showingRename = false
    @State private var titleDraft = ""
    @State private var showingTranscript = false
    @State private var preparedView = false
    @State private var offeringTitle = false
    @State private var suggestedTitle = ""
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
                Text("\(Recording.countText(item.transcript.count)) 字").monospacedDigit()
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            if showingTranscript {
            ScrollViewReader { proxy in
                ScrollView {
                    if item.lines.isEmpty {
                        Text(highlighted(item.transcript.isEmpty ? "暂无转写文字。" : item.transcript))
                            .foregroundStyle(item.transcript.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(20)
                    } else {
                        let times = cueTimes
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(item.lines) { line in
                                HStack(alignment: .top, spacing: 12) {
                                    HStack(spacing: 2) {
                                        Text(Recording.timeText(times[line.id] ?? line.time))
                                        if Recording.markedLine(line.id, among: item.lines.map { ($0.id, times[$0.id] ?? $0.time) }, marks: item.marks) {
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
                                        .highPriorityGesture(TapGesture().onEnded { player.play(from: times[line.id] ?? line.time) })
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
                    let whole = max(item.duration, player.duration)
                    let done = store.transcriptCursor
                    ProgressView(value: whole > 0 ? min(1, done / whole) : store.transcriptProgress)
                    Text("\(Recording.timeText(done)) / \(Recording.timeText(whole))")
                        .font(.caption.monospacedDigit())
                } else if store.queuedIDs.contains(item.id) {
                    Text("排队中").font(.caption).foregroundStyle(.yellow)
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
            } else {
                summaryPage
            }
        }
        .padding(.bottom, 12).background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button(item.title) { offerReplacement() }
                    .font(.headline)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("重命名", systemImage: "pencil") { titleDraft = item.title; showingRename = true }
                    Button("分享音频", systemImage: "waveform") { share(audio: true) }
                    Button("导出文字", systemImage: "doc.text") { share(audio: false) }.disabled(item.transcript.isEmpty)
                    Button(transcriptButtonTitle, systemImage: "text.bubble") { transcriptAction() }.disabled(store.queuedIDs.contains(item.id))
                    Button("查找", systemImage: "magnifyingglass") { showingFind = true }
                    Button("标记说明", systemImage: "star") { showingMarks = true }.disabled(item.marks.isEmpty)
                    Button("导出总结", systemImage: "doc.richtext") {
                        do { SystemPresenter.share(try store.shareSummary(item, text: minutesText)) }
                        catch { errorMessage = error.localizedDescription }
                    }.disabled(minutesText.isEmpty)
                    Button(item.hasSummary ? "查看总结" : "会议总结", systemImage: "sparkles") { openSummary() }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("更多操作")
            }
        }
        .alert("重命名", isPresented: $showingRename) {
            TextField("录音名称", text: $titleDraft)
            Button("保存") { item.title = Recording.cleanTitle(titleDraft); save() }
            Button("取消", role: .cancel) { }
        }
        .alert("用这个标题替换？", isPresented: $offeringTitle) {
            Button("替换") { item.title = Recording.cleanTitle(suggestedTitle); save() }
            Button("取消", role: .cancel) { }
        } message: { Text(suggestedTitle) }
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
        .onAppear {
            if !preparedView {
                preparedView = true
                showingTranscript = opensTranscript || !item.hasSummary
            }
            player.load(store.audioURL(for: item))
            findText = initialQuery
            UIApplication.shared.isIdleTimerDisabled = store.transcribingID == item.id
        }
        .onChange(of: store.summaryTick) { pullSummary() }
        .onChange(of: store.transcribingID) { UIApplication.shared.isIdleTimerDisabled = store.transcribingID == item.id }
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
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            player.stop()
            save()
        }
    }

    private var cueTimes: [UUID: TimeInterval] {
        let lines = item.lines
        guard lines.count > 1 else {
            return Dictionary(uniqueKeysWithValues: lines.map { ($0.id, max(0, $0.time)) })
        }
        let duration = max(item.duration, player.duration, 0.01)
        let unwrapped = unwrappedCueTimes(lines)
        let first = unwrapped.values.min() ?? 0
        let last = unwrapped.values.max() ?? 0
        if last - first > 1, first >= -0.1, last <= duration * 1.25 {
            return unwrapped.mapValues { min(max(0, $0), duration) }
        }
        let total = max(1, lines.reduce(0) { $0 + $1.text.count })
        var before = 0
        var map: [UUID: TimeInterval] = [:]
        for line in lines {
            map[line.id] = duration * Double(before) / Double(total)
            before += max(1, line.text.count)
        }
        return map
    }

    /// 已保存的长音频时间戳会在 3:59 后回到 0，按顺序把回绕接回真实时间。
    private func unwrappedCueTimes(_ lines: [TranscriptCue]) -> [UUID: TimeInterval] {
        var offset = 0.0
        var cycleMax = 0.0
        var map: [UUID: TimeInterval] = [:]
        for line in lines {
            let raw = max(0, line.time)
            if cycleMax > 30, raw + 20 < cycleMax {
                offset += cycleMax
                cycleMax = raw
            } else if raw > cycleMax {
                cycleMax = raw
            }
            map[line.id] = raw + offset
        }
        return map
    }

    private var activeLineID: UUID? {
        let times = cueTimes
        return item.lines.last { (times[$0.id] ?? 0) <= player.position + 0.2 }?.id ?? item.lines.first?.id
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

    private func openSummary() { showingTranscript = false }

    private func offerReplacement() {
        let theme = summaryTheme
        if !theme.isEmpty, theme != item.title {
            suggestedTitle = theme
            offeringTitle = true
        } else {
            titleDraft = item.title
            showingRename = true
        }
    }

    private var visibleSummary: String {
        let custom = item.summaryText(engine: "custom")
        if !custom.isEmpty { return custom }
        if !item.summary.isEmpty { return item.summary }
        return item.summaryDeepSeek.isEmpty ? item.summaryChatGPT : item.summaryDeepSeek
    }

    private var summaryTheme: String { Recording.subjectTitle(from: minutesText) }

    private var minutesText: String {
        if !item.summaryCustom.isEmpty { return item.summaryCustom }
        if item.summaryActions.isEmpty { return visibleSummary }
        return ""
    }

    private var summaryPage: some View {
        VStack(spacing: 0) {
            if store.summarizingID == item.id {
                ProgressView(value: store.summaryProgress) { Text("正在整理会议纪要…").font(.footnote) }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            ScrollView {
                MarkdownSummary(text: minutesText.isEmpty ? (store.summarizingID == item.id ? "正在整理…" : "还没有会议纪要。") : minutesText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .padding(.bottom, 72)
            }
            HStack {
                NavigationLink {
                    RecordingDetailView(item: item, initialQuery: initialQuery, opensTranscript: true)
                } label: {
                    Text("查看转写")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(item.hasSummary ? "重新总结" : "生成总结") { summarize() }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)
                    .disabled(store.summarizingID == item.id)
            }
            .padding(16)
        }
    }

    private func pullSummary() {
        guard let latest = store.recordings.first(where: { $0.id == item.id }) else { return }
        item.title = latest.title
        item.summary = latest.summary
        item.summaryCustom = latest.summaryCustom
        item.summaryActions = latest.summaryActions
    }

    private func summarize() {
        showingTranscript = false
        store.beginMeetingSummary(item.id, replacing: true)
    }

    private var transcriptButtonTitle: String {
        if store.queuedIDs.contains(item.id) { return "排队中" }
        if store.transcribingID == item.id { return store.transcriptPaused ? "继续转写" : "暂停转写" }
        if item.transcribedThrough > 1, item.transcribedThrough + 1 < max(item.duration, player.duration) { return "继续转写" }
        return "转写文字"
    }

    private func transcriptAction() {
        if store.queuedIDs.contains(item.id) { return }
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
        store.beginTranscription(item, from: replacing ? 0 : item.transcribedThrough)
    }
}

struct MarkdownSummary: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let line):
                    Text(inline(line)).font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline).textSelection(.enabled)
                case .paragraph(let line):
                    Text(inline(line)).font(.body).textSelection(.enabled)
                case .gap:
                    Color.clear.frame(height: 8)
                case .table(let rows):
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                    Text(inline(cell)).font(.body).textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private enum Block { case heading(Int, String), paragraph(String), gap, table([[String]]) }

    private var blocks: [Block] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\t", with: " ").components(separatedBy: "\n")
        var result: [Block] = []
        var table: [[String]] = []
        func flushTable() {
            let rows = table.compactMap { row -> [String]? in
                let cells = row.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !isRule($0) }
                return cells.isEmpty ? nil : cells
            }
            if !rows.isEmpty { result.append(.table(rows)) }
            table = []
        }
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushTable()
                if case .gap = result.last { continue }
                if !result.isEmpty { result.append(.gap) }
                continue
            }
            if isRule(line) { continue }
            if line.contains("|") {
                let cells = line.split(separator: "|", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !isRule($0) }
                if cells.count >= 2 { table.append(cells); continue }
                if cells.count == 1 { flushTable(); result.append(.paragraph(cells[0])); continue }
                continue
            }
            flushTable()
            if line.hasPrefix("### ") { result.append(.heading(3, String(line.dropFirst(4)))) }
            else if line.hasPrefix("## ") { result.append(.heading(2, String(line.dropFirst(3)))) }
            else if line.hasPrefix("# ") { result.append(.heading(1, String(line.dropFirst(2)))) }
            else { result.append(.paragraph(line)) }
        }
        flushTable()
        return result
    }

    private func isRule(_ line: String) -> Bool {
        let marks = line.filter { !$0.isWhitespace }
        return !marks.isEmpty && marks.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" }
    }

    private func inline(_ source: String) -> AttributedString {
        var line = source
        var bullet = false
        for prefix in ["* ", "- ", "+ "] where line.hasPrefix(prefix) {
            line.removeFirst(prefix.count)
            bullet = true
            break
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let parsed = (try? AttributedString(markdown: line, options: options))
            ?? AttributedString(line.replacingOccurrences(of: "*", with: ""))
        guard bullet else { return parsed }
        return AttributedString("• ") + parsed
    }
}
