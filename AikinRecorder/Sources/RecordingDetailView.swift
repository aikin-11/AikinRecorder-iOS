import SwiftUI

struct RecordingDetailView: View {
    @Environment(LibraryStore.self) private var store
    @State var item: Recording
    @State private var player = PlaybackModel()
    @State private var speech: SpeechSession?
    @State private var transcriptionTask: Task<Void, Never>?
    @State private var transcribing = false
    @State private var status = ""
    @State private var errorMessage: String?
    @State private var showingRename = false
    @State private var titleDraft = ""
    @State private var localeID = "zh-CN"
    @State private var shareURLs: [URL] = []
    @State private var showingShare = false

    var body: some View {
        @Bindable var player = player
        VStack(spacing: 16) {
            HStack {
                Text(item.createdAt, format: .dateTime.year().month().day().hour().minute())
                Spacer()
                Text(item.fileName.split(separator: ".").last?.uppercased() ?? "AUDIO")
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            TextEditor(text: $item.transcript)
                .scrollContentBackground(.hidden).padding(.horizontal, 12)
                .overlay(alignment: .topLeading) {
                    if item.transcript.isEmpty {
                        Text("暂无转写文字，可点击下方“转文字”。")
                            .foregroundStyle(.secondary).padding(.horizontal, 18).padding(.top, 9).allowsHitTesting(false)
                    }
                }
                .disabled(transcribing)
            if transcribing {
                HStack { ProgressView(); Text(status).font(.footnote); Spacer(); Button("取消") { transcriptionTask?.cancel(); Task { await speech?.cancel() }; transcribing = false } }.padding(.horizontal)
            }
            HStack {
                Picker("语言", selection: $localeID) {
                    Text("普通话").tag("zh-CN"); Text("English").tag("en-US"); Text("粤语").tag("yue-CN")
                }.disabled(transcribing)
                Spacer()
                Button("转文字", systemImage: "text.bubble") { startTranscription() }.disabled(transcribing)
                Button("保存文字", systemImage: "checkmark") { save() }.disabled(transcribing)
            }.font(.subheadline).padding(.horizontal)
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
        .padding(.bottom, 12).background(Color.black)
        .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("重命名", systemImage: "pencil") { titleDraft = item.title; showingRename = true }
                    Button("分享音频", systemImage: "waveform") { share(audio: true) }
                    Button("导出文字", systemImage: "doc.text") { share(audio: false) }.disabled(item.transcript.isEmpty)
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
        .sheet(isPresented: $showingShare) { ShareSheet(urls: shareURLs).presentationDetents([.medium, .large]) }
        .onAppear { player.load(store.audioURL(for: item)) }
        .onDisappear {
            player.stop()
            transcriptionTask?.cancel()
            let service = speech
            Task { await service?.cancel() }
            save()
        }
    }

    private func save() {
        do { try store.update(item) } catch { errorMessage = error.localizedDescription }
    }

    private func share(audio: Bool) {
        do { save(); shareURLs = [try (audio ? store.shareAudio(item) : store.shareText(item))]; showingShare = true }
        catch { errorMessage = error.localizedDescription }
    }

    private func startTranscription() {
        player.pause()
        transcribing = true
        let service = SpeechSession()
        speech = service
        let previousText = item.transcript
        service.onLines = { lines in
            item.transcript = lines.filter { !$0.provisional }.map(\.text).joined(separator: "\n")
        }
        service.onStatus = { text in status = text }
        transcriptionTask = Task {
            defer { transcribing = false }
            do {
                try await service.transcribeFile(store.audioURL(for: item), localeID: localeID)
                save()
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
                if item.transcript.isEmpty { item.transcript = previousText }
                await service.cancel()
            }
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
