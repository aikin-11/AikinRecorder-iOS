import SwiftUI

@main
struct AikinRecorderApp: App {
    @State private var library = LibraryStore()
    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(library)
                .preferredColorScheme(.dark)
                .tint(.white)
                .task {
                    while !Task.isCancelled {
                        await WebDAVSync.syncIfDue(library)
                        try? await Task.sleep(for: .seconds(30))
                    }
                }
        }
    }
}
