import MusicMemoCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// 1曲＝1ファイル（.musicmemo、中身は JSON）。
    static let musicMemoSketch = UTType(exportedAs: "local.osa.musicmemo.sketch", conformingTo: .json)
}

/// DocumentGroup で開く曲のファイル。中身は SketchFile（曲データ＋画面状態）。
struct SketchDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.musicMemoSketch] }

    var file: SketchFile

    /// 新しい曲（ひな形）。
    init() {
        file = SketchTemplate.blank()
    }

    init(file: SketchFile) {
        self.file = file
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        file = try SketchFile.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try file.encoded())
    }
}
