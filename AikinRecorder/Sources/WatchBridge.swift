import Foundation
import WatchConnectivity

@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()
    private var store: LibraryStore?

    func attach(_ store: LibraryStore) {
        self.store = store
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString).m4a")
        do { try FileManager.default.copyItem(at: file.fileURL, to: copy) } catch { return }
        Task { @MainActor in
            guard let store = self.store else { return }
            do { _ = try await store.importAudio(from: copy) }
            catch { store.errorMessage = error.localizedDescription }
        }
    }
}
