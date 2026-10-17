import SwiftUI

struct RecordingDetailView: View {
    @Environment(LibraryStore.self) private var store
    @State var item: Recording
    @State private var player = PlaybackModel()
    @State private var errorMessage: String?
    @State private var showingRename = false
    @State private var titleDraft = ""
    @State private var summarizing = false
    @State private var showingSummary = false

    var body: some View {
        @Bindable var player = player
        VStack(spacing: 16) {
            HStack {
                Text(item.createdAt, format: .dateTime.year().month().day().hour().minute())
                Spacer()
                Text(item.fileName.split(separator: ".").last?.uppercased() ?? "AUDIO")
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            ScrollView {
                if item.lines.isEmpty {
                    Text(item.transcript.isEmpty ? "暂无转写文字。" : item.transcript)
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
                                Text(line.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(20)
                }
            }
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
            Button { summarize() } label: {
                Group {
                    if summarizing { ProgressView().tint(.black) }
                    else { Image(systemName: "sparkles").font(.title3.weight(.semibold)) }
                }
                .foregroundStyle(.black)
                .frame(width: 56, height: 56)
                .background(.white, in: Circle())
            }
            .disabled(summarizing)
            .accessibilityLabel("会议总结")
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
                    Button("会议总结", systemImage: "sparkles") { summarize() }
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
            NavigationStack {
                ScrollView {
                    Text(item.summary.isEmpty ? "还没有总结。" : item.summary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
                .navigationTitle("会议总结")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingSummary = false } } }
            }
            .preferredColorScheme(.dark)
        }
        .onAppear { player.load(store.audioURL(for: item)) }
        .onDisappear { player.stop(); save() }
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

    private func summarize() {
        summarizing = true
        let transcript = item.transcript
        Task {
            defer { summarizing = false }
            do {
                item.summary = try await DeepSeekClient.summarize(transcript: transcript)
                save()
                showingSummary = true
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
