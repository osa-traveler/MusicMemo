import MusicMemoCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct MusicMemoApp: App {
    init() {
        #if DEBUG && os(macOS)
        DebugLaunch.openFileIfRequested()
        #endif
    }

    var body: some Scene {
        // 1曲＝1ファイル。iPad は起動時にファイルの一覧、Mac はファイルメニュー（新規・開く・最近使ったもの）
        DocumentGroup(newDocument: SketchDocument()) { configuration in
            SketchScreen(document: configuration.$document, fileURL: configuration.fileURL)
                #if DEBUG && os(macOS)
                .onAppear { DebugSnapshot.scheduleIfRequested() }
                #endif
        }
        .commands { SketchCommands() }
        #if os(macOS)
        .defaultSize(width: 1194, height: 834)
        #endif
        #if DEBUG && os(macOS)
        .defaultLaunchBehavior(DebugLaunch.opensSample || DebugLaunch.fileToOpen != nil ? .suppressed : .automatic)
        #endif

        #if DEBUG && os(macOS)
        // 開発用（Mac のみ）：MUSICMEMO_SAMPLE=1（または撮影・確認用の環境変数）で、サンプル曲を保存なしで直接開く
        WindowGroup("サンプル", id: "sample") {
            SketchScreen(document: .constant(SketchDocument(file: SketchFile(sketch: DebugLaunch.sample, editor: SampleData.editorState(for: DebugLaunch.sample)))), fileURL: nil)
                .onAppear { DebugSnapshot.scheduleIfRequested() }
        }
        .defaultLaunchBehavior(DebugLaunch.opensSample ? .presented : .suppressed)
        .defaultSize(width: 1194, height: 834)
        #endif
    }
}

#if DEBUG && os(macOS)
/// 開発用：サンプル曲を直接開くかどうか、起動時に開くファイル（Mac のみ）。
enum DebugLaunch {
    static let sample = SampleData.sketch03()

    /// MUSICMEMO_OPEN_FILE：起動時に開くファイル（保存と読み込みの確認用）。
    static var fileToOpen: URL? {
        ProcessInfo.processInfo.environment["MUSICMEMO_OPEN_FILE"].map { URL(fileURLWithPath: $0) }
    }

    @MainActor
    static func openFileIfRequested() {
        guard let url = fileToOpen else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { print("開けない: \(error)") }
            }
        }
    }

    /// MUSICMEMO_SAMPLE=1、または撮影・確認用の環境変数があるとき（MUSICMEMO_DOCUMENT_TEST=1 ならファイルで試すので開かない）。
    static var opensSample: Bool {
        let environment = ProcessInfo.processInfo.environment
        let isSet = { (name: String) in environment[name] != nil && environment[name] != "0" }
        if isSet("MUSICMEMO_SAMPLE") { return true }
        if isSet("MUSICMEMO_DOCUMENT_TEST") || isSet("MUSICMEMO_OPEN_FILE") { return false }
        return ["MUSICMEMO_SNAPSHOT", "MUSICMEMO_PLAY_CHECK", "MUSICMEMO_INPUT_DEMO"].contains(where: isSet)
    }
}
#endif
