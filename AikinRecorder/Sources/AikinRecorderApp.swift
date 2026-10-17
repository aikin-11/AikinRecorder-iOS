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
                .task { await WebDAVSync.syncIfDue(library) }
        }
    }
}
