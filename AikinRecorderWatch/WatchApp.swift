import AVFoundation
import SwiftUI
import WatchConnectivity
import WatchKit

@main
struct AikinRecorderWatchApp: App {
    @State private var recorder = WatchRecorder()

    var body: some Scene {
        WindowGroup {
            WatchHome(recorder: recorder)
        }
    }
}

@MainActor
final class WatchRecorder: NSObject, ObservableObject, WCSessionDelegate {
    @Published var recording = false
    @Published var elapsed = 0.0
    @Published var status = "可以开始录音"
    @Published var files: [URL] = []
    @Published var levels: [CGFloat] = Array(repeating: 0.15, count: 12)
    private var audio: AVAudioRecorder?
    private var started: Date?
    private var timer: Timer?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        refresh()
    }

    func toggle() {
        recording ? stop() : start()
    }

    func start() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [])
            try session.setActive(true)
            let url = folder().appendingPathComponent("\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            audio = try AVAudioRecorder(url: url, settings: settings)
            audio?.isMeteringEnabled = true
            audio?.record()
            levels = Array(repeating: 0.15, count: 12)
            started = .now
            recording = true
            status = "正在录音"
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let started = self.started else { return }
                    self.elapsed = Date().timeIntervalSince(started)
                    self.audio?.updateMeters()
                    let power = self.audio?.averagePower(forChannel: 0) ?? -50
                    let level = CGFloat(min(1, max(0.08, (power + 50) / 50)))
                    self.levels.removeFirst()
                    self.levels.append(level)
                }
            }
        } catch {
            status = "无法开始录音"
        }
    }

    func stop() {
        audio?.stop()
        audio = nil
        timer?.invalidate()
        recording = false
        elapsed = 0
        started = nil
        refresh()
        status = "已保存，正在传给手机"
        if let latest = files.first { send(latest) }
    }

    func send(_ url: URL) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else {
            status = "手机还没连上，录音留在手表"
            return
        }
        WCSession.default.transferFile(url, metadata: ["title": "手表录音"])
        status = "正在传到手机"
    }

    func refresh() {
        files = ((try? FileManager.default.contentsOfDirectory(at: folder(), includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func folder() -> URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        Task { @MainActor in
            status = error == nil ? "已传到手机" : "传到手机失败，录音仍在手表"
        }
    }
}

struct WatchHome: View {
    @ObservedObject var recorder: WatchRecorder

    var body: some View {
        VStack(spacing: 8) {
            Text("AikinRec").font(.headline)
            Text(recorder.recording ? time(recorder.elapsed) : recorder.status)
                .font(.caption2)
                .multilineTextAlignment(.center)
            LevelChart(levels: recorder.levels, active: recorder.recording)
                .frame(height: 36)
            Button(recorder.recording ? "停止" : "录音") { recorder.toggle() }
                .tint(recorder.recording ? .red : .yellow)
            if !recorder.files.isEmpty {
                List(recorder.files, id: \.path) { url in
                    Button("传到手机") { recorder.send(url) }
                        .font(.caption2)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func time(_ value: TimeInterval) -> String {
        let seconds = Int(value)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct LevelChart: View {
    let levels: [CGFloat]
    let active: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(active ? Color.yellow : Color.gray.opacity(0.45))
                    .frame(width: 4, height: max(4, 36 * level))
            }
        }
        .frame(maxWidth: .infinity)
    }
}
