import SwiftUI

@main
struct MusicMemoApp: App {
    var body: some Scene {
        WindowGroup {
            SketchScreen()
        }
        #if os(macOS)
        .defaultSize(width: 1194, height: 834)
        #endif
    }
}
