import SwiftUI

@main
struct MusicMemoApp: App {
    var body: some Scene {
        WindowGroup {
            SketchScreen()
                #if DEBUG && os(macOS)
                .onAppear { DebugSnapshot.scheduleIfRequested() }
                #endif
        }
        .commands { SketchCommands() }
        #if os(macOS)
        .defaultSize(width: 1194, height: 834)
        #endif
    }
}
