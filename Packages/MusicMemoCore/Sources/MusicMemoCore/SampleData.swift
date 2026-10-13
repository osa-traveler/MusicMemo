/// 基準画面（docs/screens/01_main_100.png）を再現するサンプル曲。
public enum SampleData {
    public static func sketch03() -> Sketch {
        let time = TimeSignature.common
        let bar = time.ticksPerBar
        let quarter = NoteValue.quarter.ticks
        let half = NoteValue.half.ticks
        let start = { (bar: Int, beat: Int) in time.tick(of: BarPosition(bar: bar, beat: beat)) }

        let progression = ["C", "Am", "F", "G", "C/E", "F", "Dm7", "G7", "C", "G/B", "F", "G7", "Am7"]
        let chords = progression.enumerated().map { index, symbol in
            ChordEvent(start: time.startTick(ofBar: index + 1), chord: Chord(symbol)!)
        }

        let melody: [Note] = [
            Note(start: start(5, 1), duration: quarter, pitch: 64),  // E4
            Note(start: start(5, 2), duration: quarter, pitch: 67),  // G4
            Note(start: start(5, 3), duration: half, pitch: 76),     // E5
            Note(start: start(6, 1), duration: quarter, pitch: 74),  // D5
            Note(start: start(6, 2), duration: quarter, pitch: 72),  // C5
            Note(start: start(6, 3), duration: half, pitch: 69),     // A4
        ]

        let voicings: [(bar: Int, pitches: [MIDINote])] = [
            (5, [64, 67, 72]),      // C/E: E4 G4 C5
            (6, [65, 69, 72]),      // F: F4 A4 C5
            (7, [62, 65, 69, 72]),  // Dm7: D4 F4 A4 C5
            (8, [67, 71, 74, 77]),  // G7: G4 B4 D5 F5
        ]
        let chordNotes = voicings.flatMap { voicing in
            voicing.pitches.map { Note(start: start(voicing.bar, 1), duration: bar, pitch: $0) }
        }

        let bassLine: [(bar: Int, beat: Int, pitch: MIDINote)] = [
            (5, 1, 52), (5, 3, 48),  // E3 C3
            (6, 1, 53), (6, 3, 45),  // F3 A2
            (7, 1, 50), (7, 3, 53),  // D3 F3
            (8, 1, 43), (8, 3, 47),  // G2 B2
        ]
        let bass = bassLine.map { Note(start: start($0.bar, $0.beat), duration: half, pitch: $0.pitch) }

        let pad = zip(5...8, [67, 69, 69, 71]).map {  // G4 A4 A4 B4
            Note(start: start($0, 1), duration: bar, pitch: $1)
        }

        return Sketch(
            title: "スケッチ 03",
            key: .cMajor,
            timeSignature: time,
            tempo: 96,
            barCount: 16,
            sections: [
                Section(name: "Aメロ", startBar: 1, barCount: 8),
                Section(name: "サビ", startBar: 9, barCount: 8),
            ],
            chords: chords,
            tracks: [
                Track(name: "Piano", role: .melody, color: .blue, volume: 80, pan: 0, program: 0, notes: melody),
                Track(name: "E.Piano", role: .chords, color: .orange, volume: 64, pan: -16, program: 4, notes: chordNotes),
                Track(name: "Finger Bass", role: .bass, clef: .bass, color: .green, volume: 72, pan: 0, program: 33, notes: bass),
                Track(name: "Strings", role: .pad, color: .purple, volume: 48, pan: 20, program: 48, notes: pad),
            ],
            playRange: time.startTick(ofBar: 6)..<time.startTick(ofBar: 8),
            isLooping: true
        )
    }

    /// 基準画面の画面状態：編集位置 7.1.1、メロディトラック選択、4分音符。
    public static func editorState(for sketch: Sketch) -> EditorState {
        EditorState(
            editPosition: sketch.timeSignature.tick(of: BarPosition(bar: 7)),
            selectedTrackID: sketch.tracks.first?.id,
            duration: NoteDuration(.quarter)
        )
    }
}
