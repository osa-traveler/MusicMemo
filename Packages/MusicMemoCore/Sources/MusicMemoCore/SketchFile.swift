import Foundation

/// 1曲＝1ファイル（.musicmemo）の中身。JSON で保存する。
/// 曲データに加えて、編集位置・選択中のトラック・倍率などの画面状態も保存し、開き直したときに戻す。
public struct SketchFile: Codable, Equatable, Sendable {
    /// 読める一番新しいファイル形式の版。中身の形を変えたら上げて、古い版の読み込みに対応する。
    /// - 1：最初の形
    /// - 2：ドラムのトラック（役割 drums、音部記号 percussion）。ドラムの無い曲は 1 のまま保存し、前の版のアプリでも開けるようにする
    public static let currentFormatVersion = 2

    public var formatVersion: Int
    public var sketch: Sketch
    public var editor: EditorState?

    public init(sketch: Sketch, editor: EditorState? = nil) {
        self.formatVersion = Self.formatVersion(for: sketch)
        self.sketch = sketch
        self.editor = editor
    }

    public enum ReadError: Error, Equatable {
        /// このアプリより新しい版で保存されたファイル。
        case newerFormat(Int)
    }

    /// 曲を保存するのに要る版（ドラムがあれば 2、無ければ 1）。
    public static func formatVersion(for sketch: Sketch) -> Int {
        sketch.tracks.contains(where: \.isDrums) ? 2 : 1
    }

    public func encoded() throws -> Data {
        var file = self
        file.formatVersion = Self.formatVersion(for: sketch)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    public static func decode(_ data: Data) throws -> SketchFile {
        struct Header: Decodable { var formatVersion: Int }
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard header.formatVersion <= currentFormatVersion else {
            throw ReadError.newerFormat(header.formatVersion)
        }
        return try JSONDecoder().decode(SketchFile.self, from: data)
    }
}

/// 新しい曲のひな形。
public enum SketchTemplate {
    /// C major・4/4・♩=120・16小節、セクション「Aメロ」、Piano（メロディ）・E.Piano（コード）・Finger Bass（ベース）。
    public static func blank(title: String = "無題") -> SketchFile {
        let sketch = Sketch(
            title: title,
            key: .cMajor,
            timeSignature: .common,
            tempo: 120,
            barCount: 16,
            sections: [SongSection(name: "Aメロ", startBar: 1, barCount: 16)],
            tracks: [
                Track(name: "Piano", role: .melody, color: .blue, volume: 80, program: 0),
                Track(name: "E.Piano", role: .chords, color: .orange, volume: 64, program: 4),
                Track(name: "Finger Bass", role: .bass, clef: .bass, color: .green, volume: 72, program: 33),
            ],
            playRange: 0..<(TimeSignature.common.ticksPerBar * 4)
        )
        let editor = EditorState(editPosition: 0, selectedTrackID: sketch.tracks.first?.id, duration: NoteDuration(.quarter))
        return SketchFile(sketch: sketch, editor: editor)
    }
}
