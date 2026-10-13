import Foundation
import MusicMemoCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 書き出しの形式。MusicXML（コード記号付き）を主、MIDI を従とする。
enum ExportFormat: CaseIterable {
    case musicXML
    case midi
    case both

    var title: String {
        switch self {
        case .musicXML: "MusicXML（コード付き）"
        case .midi: "MIDI"
        case .both: "MusicXML と MIDI の両方"
        }
    }
}

struct ExportFile {
    var name: String
    var data: Data
    var type: UTType
}

/// 曲をファイルにして、Mac では保存ダイアログ、iPad では共有シートで渡す。
@MainActor
enum Exporter {
    static let musicXMLType = UTType(filenameExtension: "musicxml", conformingTo: .xml) ?? .xml

    static func files(for sketch: Sketch, format: ExportFormat) -> [ExportFile] {
        let base = fileName(sketch.title)
        var files: [ExportFile] = []
        if format != .midi {
            files.append(ExportFile(name: base + ".musicxml", data: MusicXMLExporter.data(for: sketch), type: musicXMLType))
        }
        if format != .musicXML {
            files.append(ExportFile(name: base + ".mid", data: MIDIExporter.data(for: sketch), type: .midi))
        }
        return files
    }

    /// ファイル名に使えない文字を置き換える。
    static func fileName(_ title: String) -> String {
        let cleaned = title.map { "/:\\\\?%*|\"<>".contains($0) ? "_" : $0 }
        let name = String(cleaned).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "MusicMemo" : name
    }

    static func export(_ sketch: Sketch, format: ExportFormat) {
        let files = files(for: sketch, format: format)
        #if os(macOS)
        saveOnMac(files)
        #else
        shareOnIPad(files)
        #endif
    }

    #if os(macOS)
    /// 1つなら保存ダイアログ、複数ならフォルダを選んで書き出す（同名のファイルは上書きせず番号を付ける）。
    private static func saveOnMac(_ files: [ExportFile]) {
        if files.count == 1, let file = files.first {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = file.name
            panel.allowedContentTypes = [file.type]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            write(file.data, to: url)
        } else {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "ここに書き出す"
            panel.message = files.map(\.name).joined(separator: "、") + " を書き出します"
            guard panel.runModal() == .OK, let folder = panel.url else { return }
            for file in files {
                write(file.data, to: availableURL(in: folder, name: file.name))
            }
        }
    }

    private static func availableURL(in folder: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var url = folder.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(number).\(ext)")
            number += 1
        }
        return url
    }

    private static func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
    #else
    /// 一時フォルダに書いて共有シートを出す（AirDrop で Mac へ、ファイルに保存、など）。
    private static func shareOnIPad(_ files: [ExportFile]) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Export-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let urls = try files.map { file in
                let url = folder.appendingPathComponent(file.name)
                try file.data.write(to: url)
                return url
            }
            let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
            guard let presenter = topViewController() else { return }
            // iPad では共有シートをポップオーバーで出すので、位置を指定する（トップバー右上）
            controller.popoverPresentationController?.sourceView = presenter.view
            controller.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.maxX - 120, y: 40, width: 1, height: 1)
            presenter.present(controller, animated: true)
        } catch {
            print("書き出しに失敗: \(error)")
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
    #endif
}
