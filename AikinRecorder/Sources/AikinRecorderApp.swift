import SwiftUI

@main
struct AikinRecorderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var library = LibraryStore()
    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(library)
                .preferredColorScheme(.dark)
                .tint(.white)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { library.hideIsland() }
                }
                .task {
                    while !Task.isCancelled {
                        await WebDAVSync.syncIfDue(library)
                        try? await Task.sleep(for: .seconds(30))
                    }
                }
        }
    }
}
