import AVFoundation
import Observation

@MainActor @Observable
final class PlaybackModel {
    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?
    var isPlaying = false
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var errorMessage: String?

    func load(_ url: URL) {
        ticker?.cancel()
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            duration = player?.duration ?? 0
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard let self, let player = self.player else { return }
                    self.position = player.currentTime
                    self.isPlaying = player.isPlaying
                }
            }
        } catch { errorMessage = "无法播放音频：\(error.localizedDescription)" }
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying { player.pause() }
        else {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                if player.currentTime >= player.duration - 0.05 { player.currentTime = 0 }
                guard player.play() else { throw RecorderError.message("音频播放未能启动。") }
            } catch { errorMessage = error.localizedDescription }
        }
        isPlaying = player.isPlaying
    }

    func seek(_ time: TimeInterval) { player?.currentTime = min(max(0, time), duration); position = player?.currentTime ?? 0 }

    func play(from time: TimeInterval) {
        seek(time)
        guard let player else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            guard player.play() else { throw RecorderError.message("音频播放未能启动。") }
            isPlaying = true
        } catch { errorMessage = error.localizedDescription }
    }
    func pause() { player?.pause(); isPlaying = false }
    func stop() {
        player?.stop()
        ticker?.cancel()
        ticker = nil
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
