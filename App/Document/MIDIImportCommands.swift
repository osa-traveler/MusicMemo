#if os(macOS)
import AppKit
import MusicMemoCore
import os
import SwiftUI
import UniformTypeIdentifiers

/// ファイルメニューの「MIDI を読み込む…」（Mac のみ）。
/// 選んだ MIDI を曲に変換し、名前のない新しい曲として開く（元の .mid には手を付けない。保存するときに場所と名前を決める）。
/// 変換の内容は MusicMemoCore の MIDIImporter（Tools/midi2musicmemo のコマンドと共通）。
struct MIDIImportCommands: Commands {
    @Environment(\.newDocument) private var newDocument
    private static let log = Logger(subsystem: "MusicMemo", category: "MIDIImport")

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("MIDI を読み込む…") { importMIDI() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }
    }

    @MainActor
    private func importMIDI() {
        guard let url = Self.debugFile ?? chooseFile() else { return }

        let title = url.deletingPathExtension().lastPathComponent
        let result: MIDIImportResult
        do {
            result = try MIDIImporter.convert(Data(contentsOf: url), title: title)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "「\(url.lastPathComponent)」を読み込めませんでした"
            alert.informativeText = (error as? SMFError)?.description ?? error.localizedDescription
            alert.runModal()
            return
        }

        newDocument(SketchDocument(file: result.file))
        let summary = (result.report + result.warnings.map { "⚠︎ " + $0 }).joined(separator: " / ")
        Self.log.info("MIDI を読み込み: \(title, privacy: .public) — \(summary, privacy: .public)")
        guard !result.warnings.isEmpty, Self.debugFile == nil else { return }
        // 新しいウィンドウが前に出てから知らせる
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let alert = NSAlert()
            alert.messageText = "「\(url.lastPathComponent)」を読み込みました"
            alert.informativeText = "読み込めなかったもの・変えたもの：\n" + result.warnings.map { "・" + $0 }.joined(separator: "\n")
            alert.runModal()
        }
    }

    @MainActor
    private func chooseFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "MIDI を読み込む"
        panel.prompt = "読み込む"
        panel.allowedContentTypes = [.midi]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 開発用：MUSICMEMO_IMPORT_MIDI のファイル（ファイル選択を飛ばし、知らせのダイアログも出さない）。
    private static var debugFile: URL? {
        #if DEBUG
        ProcessInfo.processInfo.environment["MUSICMEMO_IMPORT_MIDI"].map { URL(fileURLWithPath: $0) }
        #else
        nil
        #endif
    }
}

#if DEBUG
/// 開発用：MUSICMEMO_IMPORT_MIDI=パス で起動すると、ファイルメニューの「MIDI を読み込む…」を実行する。
enum DebugMIDIImport {
    static var isRequested: Bool { ProcessInfo.processInfo.environment["MUSICMEMO_IMPORT_MIDI"] != nil }

    @MainActor
    static func runIfRequested() {
        guard isRequested else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let fileMenu = NSApp.mainMenu?.items.first(where: { $0.submenu?.items.contains { $0.title == "MIDI を読み込む…" } == true })?.submenu,
                  let index = fileMenu.items.firstIndex(where: { $0.title == "MIDI を読み込む…" })
            else { print("メニュー項目が見つからない"); exit(1) }
            fileMenu.performActionForItem(at: index)
        }
    }
}
#endif
#endif
