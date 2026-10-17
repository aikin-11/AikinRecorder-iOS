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
                if model.state == .idle {
                    Picker("转写方式", selection: $model.transcriptionEngine) {
                        Text("Apple 本地").tag("local")
                        Text("阿里云百炼").tag("bailian")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }
                WaveformView(levels: model.levels, moving: model.state == .recording).frame(height: 88).padding(.horizontal)
                HStack {
                    Text(Recording.timeText(model.elapsed)).font(.title2.monospacedDigit())
                    Spacer()
                    Text("\(model.lines.reduce(0) { $0 + $1.text.count }) 字").font(.subheadline.monospacedDigit())
                    Spacer()
                    Text(model.state == .paused ? "已暂停" : model.status).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }.padding(.horizontal)
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
                                        HStack(spacing: 2) {
                                            Text(Recording.timeText(line.time))
                                            if model.marks.contains(where: { abs($0.time - line.time) < 1.2 }) {
                                                Image(systemName: "star.fill").font(.system(size: 8))
                                            }
                                        }
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 78, alignment: .leading)
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
                Text("开始").font(.headline).padding(.horizontal, 36).padding(.vertical, 16)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("开始录音")
        case .preparing, .saving:
            ProgressView(model.state == .saving ? "正在保存…" : "正在准备…").padding()
        case .recording, .paused:
            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 16) {
                    Button { model.togglePause() } label: {
                        Label(model.state == .paused ? "继续" : "暂停", systemImage: model.state == .paused ? "play.fill" : "pause.fill")
                            .padding(.horizontal, 16).padding(.vertical, 16)
                    }.buttonStyle(.glass)
                    Button { model.addMark() } label: {
                        Label("标记", systemImage: "bookmark").padding(.horizontal, 16).padding(.vertical, 16)
                    }.buttonStyle(.glass)
                    Button { titleDraft = model.title; showingRename = true } label: {
                        Label("保存", systemImage: "stop.fill").padding(.horizontal, 16).padding(.vertical, 16)
                    }.buttonStyle(.glass)
                }
            }
        case .saved:
            EmptyView()
        }
    }
}

struct WaveformView: View {
    let levels: [Float]
    var moving = true
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { timeline in
            Canvas { context, size in
                let energy = levels.isEmpty ? 0.15 : levels.reduce(0, +) / Float(levels.count)
                let amplitude = max(10, CGFloat(min(1, energy)) * size.height * 0.72)
                let time = timeline.date.timeIntervalSinceReferenceDate
                let waves: [(speed: Double, freq: CGFloat, phase: Double, alpha: Double, width: CGFloat)] = [
                    (0.35, 1.1, 0, 0.95, 3.2),
                    (0.28, 1.6, 0.8, 0.72, 2.6),
                    (0.22, 0.8, 1.6, 0.55, 2.4),
                    (0.18, 2.1, 2.3, 0.4, 2.2),
                    (0.14, 1.3, 3.1, 0.28, 2)
                ]
                for wave in waves {
                    var path = Path()
                    let step = max(2, size.width / 70)
                    var x: CGFloat = 0
                    while x <= size.width {
                        let y = size.height / 2 + sin(x / size.width * .pi * 2 * wave.freq + CGFloat(time * wave.speed + wave.phase)) * amplitude
                        if x == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                        x += step
                    }
                    context.stroke(path, with: .color(.white.opacity(wave.alpha)), lineWidth: wave.width)
                }
            }
        }
        .accessibilityLabel("麦克风音量波形")
        .accessibilityHidden(true)
    }
}
