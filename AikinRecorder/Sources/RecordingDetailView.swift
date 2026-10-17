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
    @State private var transcribing = false
    @State private var speech: SpeechSession?
    @State private var findText = ""
    @State private var findIndex = 0

    var body: some View {
        @Bindable var player = player
        VStack(spacing: 16) {
            HStack {
                Text(item.createdAt, format: .dateTime.year().month().day().hour().minute())
                Spacer()
                Text(item.fileName.split(separator: ".").last?.uppercased() ?? "AUDIO")
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            HStack {
                TextField("在文本中查找", text: $findText)
                    .textFieldStyle(.roundedBorder)
                Button("上一处") { findIndex = max(0, findIndex - 1) }.font(.caption).disabled(findText.isEmpty)
                Button("下一处") { findIndex += 1 }.font(.caption).disabled(findText.isEmpty)
                Text("\(item.transcript.count) 字").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.horizontal)
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
                                    Text(Recording.timeText(line.time))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 64, alignment: .leading)
                                    Text(highlighted(line.text))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                        .contentShape(Rectangle())
                                        .onTapGesture { player.play(from: line.time) }
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
                .onChange(of: findIndex) {
                    let hits = item.lines.filter { $0.text.localizedStandardContains(findText) }
                    if findText.isEmpty || hits.isEmpty { return }
                    proxy.scrollTo(hits[min(findIndex, hits.count - 1)].id, anchor: .center)
                }
            }
            HStack {
                Button("转写文字", systemImage: "text.bubble") { transcribeImported() }
                    .disabled(transcribing)
                if transcribing { ProgressView() }
                Spacer()
            }
            .font(.subheadline)
            .padding(.horizontal)
            VStack(spacing: 8) {
                Slider(value: Binding(get: { player.position }, set: { player.seek($0) }), in: 0...max(0.01, player.duration))
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
        .overlay(alignment: .bottomTrailing) {
            Button { openSummary() } label: {
                Group {
                    if summarizing { ProgressView().tint(.black) }
                    else { Image(systemName: "sparkles").font(.title3.weight(.semibold)) }
                }
                .foregroundStyle(.black)
                .frame(width: 56, height: 56)
                .background(.white, in: Circle())
            }
            .disabled(summarizing)
            .accessibilityLabel(item.summary.isEmpty ? "会议总结" : "查看总结")
            .padding(.trailing, 20)
            .padding(.bottom, 210)
        }
        .padding(.bottom, 12).background(Color.black)
        .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("重命名", systemImage: "pencil") { titleDraft = item.title; showingRename = true }
                    Button("分享音频", systemImage: "waveform") { share(audio: true) }
                    Button("导出文字", systemImage: "doc.text") { share(audio: false) }.disabled(item.transcript.isEmpty)
                    Button("转写文字", systemImage: "text.bubble") { transcribeImported() }.disabled(transcribing)
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
        .sheet(isPresented: $showingSummary) {
            SummarySheet(summary: item.summary, progress: summaryProgress, working: summarizing) {
                do { SystemPresenter.share(try store.shareSummary(item)) }
                catch { errorMessage = error.localizedDescription }
            }
        }
        .onAppear { player.load(store.audioURL(for: item)); findText = initialQuery }
        .onDisappear {
            player.stop()
            let service = speech
            Task { await service?.cancel() }
            save()
        }
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
            } catch {
                showingSummary = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func transcribeImported() {
        player.pause()
        transcribing = true
        let service = SpeechSession()
        speech = service
        service.onLines = { lines in
            let cues = lines.filter { !$0.provisional }
            let span = max(player.duration, 1)
            item.lines = cues.enumerated().map { index, line in
                TranscriptCue(id: line.id, time: line.time > 0 ? line.time : span * Double(index) / Double(max(cues.count, 1)), text: line.text)
            }
            item.transcript = cues.map(\.text).joined(separator: "\n")
        }
        Task {
            defer { transcribing = false }
            do {
                try await service.transcribeFile(store.audioURL(for: item), localeID: "zh-CN")
                save()
            } catch { errorMessage = error.localizedDescription }
        }
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
