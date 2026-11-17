import Foundation

/// トラックの追加・複製・削除・並べ替えと、設定（名前・役割・音部記号・色・音色）の変更。
public enum TrackEditing {
    /// トラック数の上限（MIDI のチャンネルは16。10ch はドラムなので除いた15）。
    public static let maximumCount = 15

    /// 役割ごとの新しいトラックのひな形（音色・音部記号）。
    public static func template(for role: TrackRole) -> (program: Int, clef: Clef) {
        switch role {
        case .melody: (0, .treble)      // Piano
        case .chords: (4, .treble)      // E.Piano
        case .bass: (33, .bass)         // Finger Bass
        case .pad: (48, .treble)        // Strings
        case .other: (0, .treble)       // Piano
        }
    }

    /// 新しいトラックの色。まだ使っていない色を順に選び、全部使っていれば数の少ない色にする。
    public static func nextColor(in tracks: [Track]) -> TrackColor {
        let counts = Dictionary(grouping: tracks, by: \.color).mapValues(\.count)
        return TrackColor.allCases.min { counts[$0, default: 0] < counts[$1, default: 0] } ?? .blue
    }

    public static func canAdd(to sketch: Sketch) -> Bool {
        sketch.tracks.count < maximumCount
    }

    /// 役割のひな形でトラックを作り、index の位置（省略なら末尾）に入れる。作ったトラックを返す（上限なら nil）。
    @discardableResult
    public static func addTrack(role: TrackRole, at index: Int? = nil, in sketch: inout Sketch) -> Track? {
        guard canAdd(to: sketch) else { return nil }
        let template = template(for: role)
        let track = Track(name: GMInstruments.name(of: template.program), role: role, clef: template.clef,
                          color: nextColor(in: sketch.tracks), program: template.program)
        sketch.tracks.insert(track, at: min(max(index ?? sketch.tracks.count, 0), sketch.tracks.count))
        return track
    }

    /// トラックを複製してすぐ下に入れる（音符は新しい ID にする。タイのつながりは位置と高さで決まるのでそのまま）。
    @discardableResult
    public static func duplicateTrack(_ id: Track.ID, in sketch: inout Sketch) -> Track? {
        guard canAdd(to: sketch), let index = sketch.tracks.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = sketch.tracks[index]
        copy.id = UUID()
        copy.isSoloed = false
        copy.notes = copy.notes.map { note in
            var copied = note
            copied.id = UUID()
            return copied
        }
        sketch.tracks.insert(copy, at: index + 1)
        return copy
    }

    /// トラックを消す。最後の1本は消さない。消したら true。
    @discardableResult
    public static func removeTrack(_ id: Track.ID, in sketch: inout Sketch) -> Bool {
        guard sketch.tracks.count > 1, let index = sketch.tracks.firstIndex(where: { $0.id == id }) else { return false }
        sketch.tracks.remove(at: index)
        return true
    }

    /// トラックを並べ替える。destination は動かす前の並びでの挿入位置（0…トラック数。List の onMove と同じ）。
    public static func moveTrack(_ id: Track.ID, to destination: Int, in sketch: inout Sketch) {
        guard let index = sketch.tracks.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(destination, 0), sketch.tracks.count)
        guard target != index, target != index + 1 else { return }
        let track = sketch.tracks.remove(at: index)
        sketch.tracks.insert(track, at: target > index ? target - 1 : target)
    }

    /// 音色を変える。名前が今の音色名のままなら（自分で付けた名前でなければ）、名前も新しい音色名にする。
    public static func setProgram(_ program: Int, of track: inout Track) {
        if track.name == GMInstruments.name(of: track.program) {
            track.name = GMInstruments.name(of: program)
        }
        track.program = program
    }

    /// 名前を変える。前後の空白を除き、空なら音色名にする。
    public static func setName(_ name: String, of track: inout Track) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        track.name = trimmed.isEmpty ? GMInstruments.name(of: track.program) : trimmed
    }
}
