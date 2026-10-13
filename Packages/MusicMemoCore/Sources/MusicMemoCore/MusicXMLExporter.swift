import Foundation

/// MusicXML（score-partwise 4.0）への書き出し。楽器ごとに1パート。
/// コード記号はメロディのパートに付け（リードシートの形）、セクション名は練習番号、テンポは先頭パートに書く。
/// 音符の無い所は休符で埋め、小節の長さを拍子とそろえる。ミュート中のトラックも書き出す。
public enum MusicXMLExporter {
    public static func data(for sketch: Sketch) -> Data {
        Data(string(for: sketch).utf8)
    }

    public static func string(for sketch: Sketch) -> String {
        var xml = XMLWriter()
        xml.line(#"<?xml version="1.0" encoding="UTF-8" standalone="no"?>"#)
        xml.line(#"<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">"#)
        xml.open("score-partwise", attributes: [("version", "4.0")])

        xml.open("work")
        xml.element("work-title", sketch.title)
        xml.close("work")
        xml.open("identification")
        xml.open("encoding")
        xml.element("software", "MusicMemo")
        xml.close("encoding")
        xml.close("identification")

        xml.open("part-list")
        for (index, track) in sketch.tracks.enumerated() {
            let id = partID(index)
            xml.open("score-part", attributes: [("id", id)])
            xml.element("part-name", track.name)
            xml.open("score-instrument", attributes: [("id", "\(id)-I1")])
            xml.element("instrument-name", track.name)
            xml.close("score-instrument")
            xml.open("midi-instrument", attributes: [("id", "\(id)-I1")])
            xml.element("midi-channel", String(MIDIExporter.channel(forTrackAt: index) + 1))
            xml.element("midi-program", String(track.program + 1))
            xml.element("volume", String(track.volume))
            xml.element("pan", String(Int((Double(track.pan) / 64 * 90).rounded())))
            xml.close("midi-instrument")
            xml.close("score-part")
        }
        xml.close("part-list")

        let leadIndex = sketch.tracks.firstIndex { $0.role == .melody } ?? 0
        for (index, track) in sketch.tracks.enumerated() {
            writePart(track, id: partID(index), sketch: sketch,
                      isFirst: index == 0, carriesChords: index == leadIndex, into: &xml)
        }
        xml.close("score-partwise")
        return xml.text
    }

    static func partID(_ index: Int) -> String { "P\(index + 1)" }

    // MARK: パート

    private static func writePart(_ track: Track, id: String, sketch: Sketch, isFirst: Bool, carriesChords: Bool, into xml: inout XMLWriter) {
        let time = sketch.timeSignature
        var chords = Notation.chords(for: track.notes, clef: track.clef, key: sketch.key, timeSignature: time)
        _ = Notation.beamGroups(&chords, timeSignature: time)
        let tuplets = Notation.tupletGroups(chords)
        let tupletStarts = Set(tuplets.compactMap(\.first).map { chords[$0].start })
        let tupletEnds = Set(tuplets.compactMap(\.last).map { chords[$0].start })
        let tiedInto = tiedTargets(chords)
        let sectionStarts = Dictionary(sketch.sections.map { ($0.startBar, $0.name) }, uniquingKeysWith: { first, _ in first })

        xml.open("part", attributes: [("id", id)])
        for bar in 1...max(sketch.barCount, 1) {
            let barStart = time.startTick(ofBar: bar)
            let barEnd = barStart + time.ticksPerBar
            xml.open("measure", attributes: [("number", String(bar))])

            if bar == 1 { writeAttributes(track, sketch: sketch, into: &xml) }
            if isFirst {
                if bar == 1 { writeTempo(sketch.tempo, into: &xml) }
                if let name = sectionStarts[bar] { writeRehearsal(name, into: &xml) }
            }

            // 小節内の音符（はみ出す分は切る）と、隙間を埋める休符を時間順に並べる
            let inBar = chords.filter { $0.start >= barStart && $0.start < barEnd }
            let harmonies = carriesChords ? sketch.chords(inBar: bar) : []
            var position = barStart
            var pendingHarmonies = harmonies

            func emitHarmonies(from start: Tick, length: Tick) {
                let due = pendingHarmonies.filter { $0.start < start + length }
                for event in due {
                    writeHarmony(event.chord, offset: max(event.start - start, 0), into: &xml)
                }
                pendingHarmonies.removeAll { $0.start < start + length }
            }

            func fillRest(to end: Tick) {
                guard end > position else { return }
                if position == barStart && end == barEnd && inBar.isEmpty {
                    emitHarmonies(from: position, length: end - position)
                    writeMeasureRest(time.ticksPerBar, into: &xml)
                    position = end
                    return
                }
                for segment in NoteEditing.split(position..<end, timeSignature: time) {
                    emitHarmonies(from: segment.lowerBound, length: segment.count)
                    writeNote(nil, duration: segment.count, value: NoteDuration(ticks: segment.count), isChordMember: false,
                              tieStart: false, tieStop: false, tuplet: nil, stemUp: nil, into: &xml)
                }
                position = end
            }

            for chord in inBar {
                fillRest(to: chord.start)
                guard chord.start >= position else { continue }  // 前の音と重なる音は書かない（声部は1つ）
                let length = min(chord.end, barEnd) - chord.start
                emitHarmonies(from: chord.start, length: length)
                let tuplet: String? = tupletStarts.contains(chord.start) ? "start" : tupletEnds.contains(chord.start) ? "stop" : nil
                if chord.isRest {
                    writeNote(nil, duration: length, value: chord.value, isChordMember: false,
                              tieStart: false, tieStop: false, tuplet: tuplet, stemUp: nil, into: &xml)
                } else {
                    for (index, head) in chord.heads.enumerated() {
                        writeNote(head, duration: length, value: chord.value, isChordMember: index > 0,
                                  tieStart: head.tiesToNext, tieStop: tiedInto.contains(TieKey(start: chord.start, pitch: head.pitch)),
                                  tuplet: index == 0 ? tuplet : nil, stemUp: chord.value.hasStem ? chord.stemUp : nil,
                                  key: sketch.key, into: &xml)
                    }
                }
                position = chord.start + length
            }
            fillRest(to: barEnd)

            if bar == sketch.barCount {
                xml.open("barline", attributes: [("location", "right")])
                xml.element("bar-style", "light-heavy")
                xml.close("barline")
            }
            xml.close("measure")
        }
        xml.close("part")
    }

    private struct TieKey: Hashable {
        var start: Tick
        var pitch: MIDINote
    }

    /// タイで入ってくる音（タイの終わり）。
    private static func tiedTargets(_ chords: [NotatedChord]) -> Set<TieKey> {
        var result = Set<TieKey>()
        for chord in chords {
            for head in chord.heads where head.tiesToNext {
                result.insert(TieKey(start: chord.end, pitch: head.pitch))
            }
        }
        return result
    }

    // MARK: 要素

    private static func writeAttributes(_ track: Track, sketch: Sketch, into xml: inout XMLWriter) {
        xml.open("attributes")
        xml.element("divisions", String(Timing.ticksPerQuarter))
        xml.open("key")
        xml.element("fifths", String(KeySignature(sketch.key).fifths))
        xml.element("mode", sketch.key.mode.rawValue)
        xml.close("key")
        xml.open("time")
        xml.element("beats", String(sketch.timeSignature.beats))
        xml.element("beat-type", String(sketch.timeSignature.beatUnit))
        xml.close("time")
        xml.open("clef")
        switch track.clef {
        case .treble:
            xml.element("sign", "G")
            xml.element("line", "2")
        case .bass:
            xml.element("sign", "F")
            xml.element("line", "4")
        }
        xml.close("clef")
        xml.close("attributes")
    }

    private static func writeTempo(_ tempo: Double, into xml: inout XMLWriter) {
        let perMinute = tempo.rounded() == tempo ? String(Int(tempo)) : String(tempo)
        xml.open("direction", attributes: [("placement", "above")])
        xml.open("direction-type")
        xml.open("metronome")
        xml.element("beat-unit", "quarter")
        xml.element("per-minute", perMinute)
        xml.close("metronome")
        xml.close("direction-type")
        xml.empty("sound", attributes: [("tempo", perMinute)])
        xml.close("direction")
    }

    private static func writeRehearsal(_ name: String, into xml: inout XMLWriter) {
        xml.open("direction", attributes: [("placement", "above")])
        xml.open("direction-type")
        xml.element("rehearsal", name)
        xml.close("direction-type")
        xml.close("direction")
    }

    private static func writeHarmony(_ chord: Chord, offset: Tick, into xml: inout XMLWriter) {
        let (kind, degrees) = harmonyKind(chord.quality)
        xml.open("harmony")
        xml.open("root")
        let root = spell(chord.root, preferFlats: chord.prefersFlats)
        xml.element("root-step", root.step)
        if root.alter != 0 { xml.element("root-alter", String(root.alter)) }
        xml.close("root")
        xml.element("kind", kind, attributes: [("text", chord.quality.rawValue)])
        if let bass = chord.bass {
            let spelled = spell(bass, preferFlats: chord.prefersFlats)
            xml.open("bass")
            xml.element("bass-step", spelled.step)
            if spelled.alter != 0 { xml.element("bass-alter", String(spelled.alter)) }
            xml.close("bass")
        }
        for (value, alter) in degrees {
            xml.open("degree")
            xml.element("degree-value", String(value))
            xml.element("degree-alter", String(alter))
            xml.element("degree-type", "add")
            xml.close("degree")
        }
        if offset > 0 { xml.element("offset", String(offset)) }
        xml.close("harmony")
    }

    private static func writeMeasureRest(_ duration: Tick, into xml: inout XMLWriter) {
        xml.open("note")
        xml.empty("rest", attributes: [("measure", "yes")])
        xml.element("duration", String(duration))
        xml.element("voice", "1")
        xml.close("note")
    }

    private static func writeNote(
        _ head: NotatedHead?, duration: Tick, value: NoteDuration, isChordMember: Bool,
        tieStart: Bool, tieStop: Bool, tuplet: String?, stemUp: Bool?, key: Key = .cMajor, into xml: inout XMLWriter
    ) {
        xml.open("note")
        if isChordMember { xml.empty("chord") }
        if let head {
            let spelled = SpelledPitch(head.pitch, in: key)
            xml.open("pitch")
            xml.element("step", String("CDEFGAB"[String.Index(utf16Offset: spelled.letter, in: "CDEFGAB")]))
            if spelled.alter != 0 { xml.element("alter", String(spelled.alter)) }
            xml.element("octave", String(spelled.octave))
            xml.close("pitch")
        } else {
            xml.empty("rest")
        }
        xml.element("duration", String(duration))
        if tieStop { xml.empty("tie", attributes: [("type", "stop")]) }
        if tieStart { xml.empty("tie", attributes: [("type", "start")]) }
        xml.element("voice", "1")
        xml.element("type", typeName(value.value))
        if value.isDotted { xml.empty("dot") }
        if let alter = head?.accidental {
            xml.element("accidental", alter == 1 ? "sharp" : alter == -1 ? "flat" : "natural")
        }
        if value.isTriplet {
            xml.open("time-modification")
            xml.element("actual-notes", "3")
            xml.element("normal-notes", "2")
            xml.close("time-modification")
        }
        if let stemUp { xml.element("stem", stemUp ? "up" : "down") }
        if tieStart || tieStop || tuplet != nil {
            xml.open("notations")
            if tieStop { xml.empty("tied", attributes: [("type", "stop")]) }
            if tieStart { xml.empty("tied", attributes: [("type", "start")]) }
            if let tuplet { xml.empty("tuplet", attributes: [("type", tuplet)]) }
            xml.close("notations")
        }
        xml.close("note")
    }

    static func typeName(_ value: NoteValue) -> String {
        switch value {
        case .whole: "whole"
        case .half: "half"
        case .quarter: "quarter"
        case .eighth: "eighth"
        case .sixteenth: "16th"
        }
    }

    /// コードの質 → MusicXML の kind（足りない音は degree で足す）。
    static func harmonyKind(_ quality: ChordQuality) -> (String, [(Int, Int)]) {
        switch quality {
        case .major: ("major", [])
        case .minor: ("minor", [])
        case .dominant7: ("dominant", [])
        case .major7: ("major-seventh", [])
        case .minor7: ("minor-seventh", [])
        case .diminished: ("diminished", [])
        case .augmented: ("augmented", [])
        case .sus4: ("suspended-fourth", [])
        case .sus2: ("suspended-second", [])
        case .sixth: ("major-sixth", [])
        case .minor6: ("minor-sixth", [])
        case .ninth: ("dominant-ninth", [])
        case .major9: ("major-ninth", [])
        case .minor9: ("minor-ninth", [])
        case .add9: ("major", [(9, 0)])
        case .minor7Flat5: ("half-diminished", [])
        case .diminished7: ("diminished-seventh", [])
        case .dominant7Sus4: ("suspended-fourth", [(7, -1)])
        case .minorMajor7: ("major-minor", [])
        }
    }

    /// ピッチクラスを音名（幹音＋変化）にする。
    static func spell(_ pitchClass: PitchClass, preferFlats: Bool) -> (step: String, alter: Int) {
        let name = Pitch.name(of: pitchClass, preferFlats: preferFlats)
        let alter = name.count > 1 ? (name.hasSuffix("b") ? -1 : 1) : 0
        return (String(name.prefix(1)), alter)
    }
}

/// インデント付きで XML を組み立てる。
struct XMLWriter {
    private(set) var text = ""
    private var depth = 0

    mutating func line(_ string: String) {
        text += String(repeating: "  ", count: depth) + string + "\n"
    }

    mutating func open(_ name: String, attributes: [(String, String)] = []) {
        line("<\(name)\(Self.format(attributes))>")
        depth += 1
    }

    mutating func close(_ name: String) {
        depth -= 1
        line("</\(name)>")
    }

    mutating func element(_ name: String, _ value: String, attributes: [(String, String)] = []) {
        line("<\(name)\(Self.format(attributes))>\(Self.escape(value))</\(name)>")
    }

    mutating func empty(_ name: String, attributes: [(String, String)] = []) {
        line("<\(name)\(Self.format(attributes))/>")
    }

    private static func format(_ attributes: [(String, String)]) -> String {
        attributes.map { " \($0.0)=\"\(escape($0.1))\"" }.joined()
    }

    static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
