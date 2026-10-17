import SwiftUI

struct RecorderView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var model = RecorderModel()
    @State private var preparingTask: Task<Void, Never>?
    @State private var confirmingClose = false
    @State private var showingRename = false
    @State private var titleDraft = ""

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 20) {
                TextField("录音名称", text: $model.title, axis: .vertical)
                    .font(.headline).lineLimit(2...3).padding(.horizontal)
                    .accessibilityLabel("录音名称")
                WaveformView(levels: model.levels).frame(height: 70).padding(.horizontal)
                HStack {
                    Text(Recording.timeText(model.elapsed)).font(.title2.monospacedDigit())
                    Spacer()
                    Text(model.state == .paused ? "已暂停" : model.status).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }.padding(.horizontal)
                if model.state == .idle {
                    VStack(spacing: 16) {
                        Toggle("实时转写", isOn: $model.liveTranscription)
                        Picker("转写语言", selection: $model.localeID) {
                            Text("普通话").tag("zh-CN")
                            Text("English").tag("en-US")
                            Text("粤语").tag("yue-CN")
                        }
                        Text("使用 Apple 本地语音模型。首次使用可能需要下载语言资源；音频保存在本机。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(20).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        if model.lines.isEmpty {
                            Text("靠近手机讲话，转写文字会显示在这里。")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20)
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(model.lines) { line in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(Recording.timeText(line.time))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 64, alignment: .leading)
                                            .accessibilityLabel("时间 \(Recording.timeText(line.time))")
                                        Text(line.text)
                                            .foregroundStyle(line.provisional ? .secondary : .primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                    .id(line.id)
                                }
                            }
                            .padding(20)
                        }
                    }
                    .onChange(of: model.lines.last?.text) {
                        if let id = model.lines.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
                controls.padding(.bottom, 20)
            }
            .padding(.top)
            .background(Color.black)
            .navigationTitle("录音实时转写").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.state == .saved ? "完成" : "关闭") {
                        if model.hasUnsavedRecording { confirmingClose = true }
                        else { preparingTask?.cancel(); dismiss() }
                    }.disabled(model.state == .saving)
                }
            }
            .interactiveDismissDisabled(model.hasUnsavedRecording || model.state == .preparing)
            .confirmationDialog("保存录音后退出？", isPresented: $confirmingClose, titleVisibility: .visible) {
                Button("保存并退出") { Task { await model.finish(in: store); dismiss() } }
            }
            .alert("保存录音", isPresented: $showingRename) {
                TextField("录音名称", text: $titleDraft)
                Button("保存") {
                    model.title = titleDraft
                    Task { await model.finish(in: store) }
                }
                Button("取消", role: .cancel) { }
            } message: { Text("确认名称后再保存。") }
            .alert("提示", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("好") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
        }
        .preferredColorScheme(.dark).tint(.white)
    }

    @ViewBuilder private var controls: some View {
        switch model.state {
        case .idle:
            Button { preparingTask = Task { await model.start(in: store) } } label: {
                Image(systemName: "mic.fill").font(.system(size: 27)).foregroundStyle(.black)
                    .frame(width: 76, height: 76).background(.white, in: Circle())
            }.accessibilityLabel("开始录音")
        case .preparing, .saving:
            ProgressView(model.state == .saving ? "正在保存…" : "正在准备…").padding()
        case .recording, .paused:
            GlassEffectContainer(spacing: 24) {
                HStack(spacing: 36) {
                    Button { model.togglePause() } label: {
                        Label(model.state == .paused ? "继续" : "暂停", systemImage: model.state == .paused ? "play.fill" : "pause.fill")
                            .padding(.horizontal, 22).padding(.vertical, 16)
                    }.buttonStyle(.glass)
                    Button { titleDraft = model.title; showingRename = true } label: {
                        Label("保存", systemImage: "stop.fill").padding(.horizontal, 22).padding(.vertical, 16)
                    }.buttonStyle(.glass)
                }
            }
        case .saved:
            Button("完成") { dismiss() }.buttonStyle(.glass).controlSize(.large)
        }
    }
}

struct WaveformView: View {
    let levels: [Float]
    var body: some View {
        Canvas { context, size in
            let count = CGFloat(max(levels.count, 1))
            let spacing: CGFloat = 3
            let width = max(2, (size.width - spacing * (count - 1)) / count)
            for index in levels.indices {
                let height = max(2, CGFloat(levels[index]) * size.height)
                let x = CGFloat(index) * (width + spacing)
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: width, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(.white.opacity(0.75)))
            }
        }
        .accessibilityLabel("麦克风音量波形")
        .accessibilityHidden(true)
    }
}
