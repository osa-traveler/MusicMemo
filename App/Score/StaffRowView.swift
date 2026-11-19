import MusicMemoCore
import SwiftUI

/// 1トラック分の五線（横スクロールするコンテンツ）。小節線・拍子記号・音符を描く。
struct StaffRowView: View {
    let track: Track
    let sketch: Sketch
    let editor: EditorState
    let layout: ScoreLayout
    let rowHeight: CGFloat
    /// 選んでいる音符（このトラックのもの）。
    var selectedNoteIDs: Set<Note.ID> = []
    /// ドラッグ中の移動先（半透明の青で出す）。
    var dragPreview: [Note] = []
    /// 範囲選択の箱（行の座標）。
    var selectionBox: CGRect?
    /// 選んだ音符をドラッグしている（移動量）／離した。
    var onDragSelection: (CGSize) -> Void = { _ in }
    var onEndDragSelection: () -> Void = {}

    private var isSelected: Bool { editor.selectedTrackID == track.id }

    /// 描く音符（記譜用に変換したもの）。長さの違う音が重なるところは2つの声部に分ける。
    struct StaffNotation {
        var voices: [Notation.NotatedVoice]
        /// 全部の声部の音符（当たり判定・選択の表示用）。
        var chords: [NotatedChord] { voices.flatMap(\.chords) }
    }

    /// 記譜の元になる値。これが同じなら、前に計算した記譜を使う。
    private struct NotationKey: Equatable {
        var notes: [Note]
        var clef: Clef
        var key: Key
        var timeSignature: TimeSignature
    }

    /// トラックごとに、最後に計算した記譜を覚えておく（五線・鳴っている音の表示・当たり判定で共有する）。
    private static var notationCache: [Track.ID: (key: NotationKey, notation: StaffNotation)] = [:]

    static func notation(of track: Track, sketch: Sketch, layout: ScoreLayout) -> StaffNotation {
        notation(of: track, key: sketch.key, timeSignature: layout.timeSignature)
    }

    static func notation(of track: Track, key: Key, timeSignature: TimeSignature) -> StaffNotation {
        let cacheKey = NotationKey(notes: track.notes, clef: track.clef, key: key, timeSignature: timeSignature)
        if let cached = notationCache[track.id], cached.key == cacheKey { return cached.notation }
        let notation = StaffNotation(voices: Notation.voices(for: track.notes, clef: track.clef, key: key, timeSignature: timeSignature))
        notationCache[track.id] = (cacheKey, notation)
        return notation
    }

    /// point（行の座標）にある音符・休符。一番近い符頭を選ぶ。
    static func hitNote(at point: CGPoint, track: Track, sketch: Sketch, layout: ScoreLayout, rowHeight: CGFloat) -> Note.ID? {
        let chords = notation(of: track, sketch: sketch, layout: layout).chords
        let drawing = NoteDrawing(layout: layout, bottomLineY: layout.bottomLineY(rowHeight: rowHeight), color: Palette.ink)
        let hit = drawing.hitTargets(chords)
            .compactMap { target in target.distance(to: point).map { (target, $0) } }
            .min { $0.1 < $1.1 }?.0
        guard let hit else { return nil }
        return track.notes.first { $0.start == hit.start && $0.pitch == hit.pitch }?.id
    }

    /// 箱（行の座標）の中に符頭（休符）の中心がある音符。
    static func notes(in rect: CGRect, track: Track, sketch: Sketch, layout: ScoreLayout, rowHeight: CGFloat) -> [Note.ID] {
        let chords = notation(of: track, sketch: sketch, layout: layout).chords
        let drawing = NoteDrawing(layout: layout, bottomLineY: layout.bottomLineY(rowHeight: rowHeight), color: Palette.ink)
        let hits = drawing.hitTargets(chords).filter { rect.contains($0.center) }
        return track.notes.filter { note in hits.contains { $0.start == note.start && $0.pitch == note.pitch } }.map(\.id)
    }

    /// 五線を描くタイルの幅。画面に入ったタイルだけを作って描く（曲全体を1枚で描くと、長い曲ではスクロールのたびの描き直しが重い）。
    static let tileWidth: CGFloat = 800

    var body: some View {
        #if DEBUG
        let _ = FrameProbe.staffBodies += 1
        #endif
        let notation = Self.notation(of: track, sketch: sketch, layout: layout)
        let voices = notation.voices
        let chords = notation.chords
        let selectedNotes = track.notes.filter { selectedNoteIDs.contains($0.id) }
        let contentWidth = layout.contentWidth
        let tileCount = max(Int((contentWidth / Self.tileWidth).rounded(.up)), 1)
        LazyHStack(spacing: 0) {
            ForEach(Array(0..<tileCount), id: \.self) { index in
                let minX = CGFloat(index) * Self.tileWidth
                let width = max(min(Self.tileWidth, contentWidth - minX), 0)
                Canvas { [voices, chords, selectedNotes] context, size in
                    #if DEBUG
                    let probeStart = ContinuousClock.now
                    defer { FrameProbe.recordDraw(since: probeStart) }
                    #endif
                    var context = context
                    context.translateBy(x: -minX, y: 0)
                    // タイルの外に少しはみ出す記号（臨時記号・付点・旗・コードネーム）の分だけ広く見る
                    let margin = 60 * layout.zoom
                    draw(visible: (minX - margin)...(minX + width + margin), tile: minX...(minX + width), rowHeight: size.height,
                         voices: voices, chords: chords, selectedNotes: selectedNotes, in: context)
                }
                .frame(width: width, height: rowHeight)
            }
        }
        .frame(width: contentWidth, height: rowHeight, alignment: .leading)
        .overlay(alignment: .topLeading) {
            selectionHandles(chords: chords, selectedNotes: selectedNotes)
        }
    }

    /// 五線の中身を描く（コンテンツ座標）。visible にかかるものだけを描く。tile は五線を引く範囲。
    private func draw(visible: ClosedRange<CGFloat>, tile: ClosedRange<CGFloat>, rowHeight: CGFloat, voices: [Notation.NotatedVoice],
                      chords: [NotatedChord], selectedNotes: [Note], in context: GraphicsContext) {
        let bottom = layout.bottomLineY(rowHeight: rowHeight)
        if isSelected {
            drawInputBar(rowHeight: rowHeight, in: context)
        }
        if layout.showsDetail {
            drawEighthGrid(bottomLineY: bottom, visible: visible, in: context)
        }
        StaffDrawing.staffLines(from: tile.lowerBound, to: tile.upperBound, bottomLineY: bottom, layout: layout, in: context)
        drawBarLines(bottomLineY: bottom, visible: visible, in: context)
        if visible.contains(layout.stickyWidth) {
            drawTimeSignature(bottomLineY: bottom, in: context)
        }
        if track.showsChordSymbols {
            drawChordSymbols(bottomLineY: bottom, visible: visible, in: context)
        }
        let notes = NoteDrawing(layout: layout, bottomLineY: bottom, color: Palette.ink)
        for voice in voices {
            drawVoice(voice, with: notes, visible: visible, in: context)
        }
        if !selectedNotes.isEmpty {
            let selection = NoteDrawing(layout: layout, bottomLineY: bottom, color: Palette.accent)
            for chord in chords where overlaps(chord.start, chord.start, visible) {
                let here = selectedNotes.filter { $0.start == chord.start }
                guard !here.isEmpty else { continue }
                selection.drawSelected(chord, pitches: Set(here.compactMap(\.pitch)), in: context)
            }
        }
        if let selectionBox {
            let box = Path(selectionBox.insetBy(dx: 0.5, dy: 0.5))
            context.fill(box, with: .color(Palette.accent.opacity(0.08)))
            context.stroke(box, with: .color(Palette.accent.opacity(0.7)), lineWidth: 1)
        }
        if !dragPreview.isEmpty {
            drawDragPreview(bottomLineY: bottom, in: context)
        } else if isSelected, selectedNotes.isEmpty {
            drawPreviewNote(bottomLineY: bottom, in: context)
        }
    }

    /// tick の start〜end（音符の位置）が visible にかかるか。
    private func overlaps(_ start: Tick, _ end: Tick, _ visible: ClosedRange<CGFloat>) -> Bool {
        layout.x(tick: end) >= visible.lowerBound && layout.x(tick: start) <= visible.upperBound
    }

    /// 1つの声部の音符・連桁・タイ・3連符。
    /// visible にかかる音符・連桁・タイ・3連符だけを描く。
    private func drawVoice(_ voice: Notation.NotatedVoice, with notes: NoteDrawing, visible: ClosedRange<CGFloat>, in context: GraphicsContext) {
        let chords = voice.chords
        let beamed = Set(voice.beamGroups.joined())
        let groupVisible = { (group: [Int]) in
            guard let first = group.first, let last = group.last else { return false }
            return overlaps(chords[first].start, chords[last].start, visible)
        }
        for (index, chord) in chords.enumerated() where !beamed.contains(index) && overlaps(chord.start, chord.start, visible) {
            notes.draw(chord, in: context)
        }
        for group in voice.beamGroups where groupVisible(group) {
            notes.drawBeamGroup(group.map { chords[$0] }, in: context)
        }
        // タイの行き先は同じ声部の中で探す
        let chordsByStart = Dictionary(chords.map { ($0.start, $0) }, uniquingKeysWith: { first, _ in first })
        for chord in chords where chord.heads.contains(where: \.tiesToNext) && overlaps(chord.start, chord.end, visible) {
            notes.drawTies(chord, next: chordsByStart[chord.end], in: context)
        }
        for group in voice.tuplets where groupVisible(group) {
            notes.drawTuplet(group.map { chords[$0] }, in: context)
        }
    }

    /// 選んだ音符の上に置くドラッグ用の領域。ここから始めたドラッグだけを移動にし、それ以外は譜面のスクロールに任せる（iPad）。
    /// 複数選んでいるときは、どれをつかんでも全部が一緒に動く。
    private func selectionHandles(chords: [NotatedChord], selectedNotes: [Note]) -> some View {
        let drawing = NoteDrawing(layout: layout, bottomLineY: layout.bottomLineY(rowHeight: rowHeight), color: Palette.accent)
        let targets = drawing.hitTargets(chords).filter { target in
            selectedNotes.contains { $0.start == target.start && $0.pitch == target.pitch }
        }
        return ZStack(alignment: .topLeading) {
            ForEach(Array(targets.enumerated()), id: \.offset) { _, target in
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: target.size.width, height: target.size.height)
                    .position(target.center)
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { onDragSelection($0.translation) }
                            .onEnded { _ in onEndDragSelection() }
                    )
            }
        }
        .frame(width: layout.contentWidth, height: rowHeight, alignment: .topLeading)
    }

    /// ドラッグ中の移動先（半透明の青）。
    private func drawDragPreview(bottomLineY: CGFloat, in context: GraphicsContext) {
        let preview = Notation.chords(for: dragPreview, clef: track.clef, key: sketch.key, timeSignature: layout.timeSignature)
        let drawing = NoteDrawing(layout: layout, bottomLineY: bottomLineY, color: Palette.accent.opacity(0.5))
        for chord in preview {
            drawing.draw(chord, in: context)
        }
    }

    /// 入力中の小節（編集位置の小節）を薄い青で塗る。
    private func drawInputBar(rowHeight: CGFloat, in context: GraphicsContext) {
        let bar = layout.timeSignature.bar(containing: editor.editPosition)
        let rect = layout.inputBarRect(bar: bar, rowHeight: rowHeight)
        context.fill(Path(roundedRect: rect, cornerRadius: 6 * layout.zoom), with: .color(Palette.accent.opacity(0.08)))
    }

    /// 拡大時、8分ごとの薄い縦線（五線の少し上下まで）。
    private func drawEighthGrid(bottomLineY: CGFloat, visible: ClosedRange<CGFloat>, in context: GraphicsContext) {
        let time = layout.timeSignature
        let eighth = Timing.ticksPerQuarter / 2
        let top = layout.y(staffPosition: 12, bottomLineY: bottomLineY)
        let bottom = layout.y(staffPosition: -4, bottomLineY: bottomLineY)
        var path = Path()
        for tick in stride(from: 0, to: layout.barCount * time.ticksPerBar, by: eighth) {
            let x = layout.x(tick: tick)
            guard visible.contains(x) else { continue }
            path.move(to: CGPoint(x: x, y: top))
            path.addLine(to: CGPoint(x: x, y: bottom))
        }
        context.stroke(path, with: .color(Palette.ruleSoft), lineWidth: 1)
    }

    /// コードトラックの五線の上にコードネーム（オレンジ）。
    private func drawChordSymbols(bottomLineY: CGFloat, visible: ClosedRange<CGFloat>, in context: GraphicsContext) {
        let baselineY = layout.y(staffPosition: 8, bottomLineY: bottomLineY) - layout.chordSymbolOffset
        // コードネームは右へ伸びるので、左は長めに見る
        let reach = 160 * layout.zoom
        for event in sketch.chords {
            let x = layout.x(tick: event.start)
            guard x >= visible.lowerBound - reach, x <= visible.upperBound else { continue }
            let text = context.resolve(
                Text(event.chord.symbol)
                    .font(.system(size: layout.textSize(15), weight: .bold))
                    .foregroundStyle(Palette.chord)
            )
            let size = text.measure(in: CGSize(width: CGFloat.infinity, height: .infinity))
            let origin = CGPoint(x: layout.x(tick: event.start) + layout.chordSymbolLeading,
                                 y: baselineY - text.firstBaseline(in: size))
            context.draw(text, in: CGRect(origin: origin, size: size))
        }
    }

    /// 入力予定の音符（半透明の青）。
    private func drawPreviewNote(bottomLineY: CGFloat, in context: GraphicsContext) {
        guard let pitch = editor.previewPitch else { return }
        let note = Note(start: editor.editPosition, duration: editor.duration.ticks, pitch: pitch)
        let preview = Notation.chords(for: [note], clef: track.clef, key: sketch.key, timeSignature: layout.timeSignature)
        let drawing = NoteDrawing(layout: layout, bottomLineY: bottomLineY, color: Palette.accent.opacity(0.45))
        for chord in preview {
            drawing.draw(chord, in: context)
        }
    }

    private func drawBarLines(bottomLineY: CGFloat, visible: ClosedRange<CGFloat>, in context: GraphicsContext) {
        let top = layout.y(staffPosition: 8, bottomLineY: bottomLineY)
        var path = Path()
        for bar in 1...(layout.barCount + 1) {
            let x = layout.barLineX(bar: bar)
            guard visible.contains(x) else { continue }
            path.move(to: CGPoint(x: x, y: top))
            path.addLine(to: CGPoint(x: x, y: bottomLineY))
        }
        context.stroke(path, with: .color(Palette.ink), lineWidth: StaffDrawing.thinLineWidth(layout))
    }

    private func drawTimeSignature(bottomLineY: CGFloat, in context: GraphicsContext) {
        let time = layout.timeSignature
        let x = layout.stickyWidth + 2 * layout.zoom
        for (number, position) in [(time.beats, 6), (time.beatUnit, 2)] {
            let digits = String(number).compactMap(\.wholeNumberValue)
            var digitX = x
            for digit in digits {
                SMuFL.draw(.timeSigDigit(digit),
                           at: CGPoint(x: digitX, y: layout.y(staffPosition: position, bottomLineY: bottomLineY)),
                           staffSpace: layout.staffSpace, color: Palette.ink, in: context)
                digitX += 1.8 * layout.staffSpace
            }
        }
    }
}

/// 中身（トラック・曲・画面状態・倍率・選択など）が同じなら作り直さない。
/// 操作のクロージャはいつも同じ store の操作を呼ぶだけなので比べない（比べられないクロージャがあると、
/// 横スクロールのたびに全トラックの記譜を計算し直して、再生中のページ送りで画面が止まっていた）。
extension StaffRowView: Equatable {
    nonisolated static func == (lhs: StaffRowView, rhs: StaffRowView) -> Bool {
        lhs.track == rhs.track && lhs.sketch == rhs.sketch && lhs.editor == rhs.editor && lhs.layout == rhs.layout
            && lhs.rowHeight == rhs.rowHeight && lhs.selectedNoteIDs == rhs.selectedNoteIDs
            && lhs.dragPreview == rhs.dragPreview && lhs.selectionBox == rhs.selectionBox
    }
}

/// 左端に固定する音部記号と調号（横スクロールしても動かない）。
struct StickyClefView: View {
    let track: Track
    let layout: ScoreLayout
    let rowHeight: CGFloat
    /// 表示領域の左端にある小節の番号（先頭トラックだけに出す）。
    let leadingBarNumber: Int?

    var body: some View {
        Canvas { context, size in
            let bottom = layout.bottomLineY(rowHeight: size.height)
            StaffDrawing.staffLines(from: 0, to: size.width, bottomLineY: bottom, layout: layout, in: context)
            drawClef(bottomLineY: bottom, in: context)
            drawKeySignature(bottomLineY: bottom, in: context)
            if let leadingBarNumber {
                let top = layout.y(staffPosition: 8, bottomLineY: bottom)
                context.draw(
                    Text("\(leadingBarNumber)").font(.system(size: layout.textSize(10, minimumScale: 0.9))).foregroundStyle(Palette.inkTertiary),
                    at: CGPoint(x: 10 * layout.zoom, y: top - 14 * layout.zoom),
                    anchor: .bottomLeading
                )
            }
        }
        .frame(width: layout.stickyWidth, height: rowHeight)
        .background(Palette.paper)
    }

    private func drawClef(bottomLineY: CGFloat, in context: GraphicsContext) {
        // SMuFL の音部記号は、ト音記号は G の線（第2線）、ヘ音記号は F の線（第4線）が基準点
        let (glyph, position): (Glyph, Int) = switch track.clef {
        case .treble: (.gClef, 2)
        case .bass: (.fClef, 6)
        }
        SMuFL.draw(glyph,
                   at: CGPoint(x: layout.clefX, y: layout.y(staffPosition: position, bottomLineY: bottomLineY)),
                   staffSpace: layout.staffSpace, color: Palette.ink, in: context)
    }

    private func drawKeySignature(bottomLineY: CGFloat, in context: GraphicsContext) {
        let signature = layout.keySignature
        let glyph: Glyph = signature.fifths >= 0 ? .accidentalSharp : .accidentalFlat
        for (index, position) in signature.staffPositions(for: track.clef).enumerated() {
            let x = layout.keySignatureX + CGFloat(index) * layout.keySignatureAdvance
            SMuFL.draw(glyph,
                       at: CGPoint(x: x, y: layout.y(staffPosition: position, bottomLineY: bottomLineY)),
                       staffSpace: layout.staffSpace, color: Palette.ink, in: context)
        }
    }
}

enum StaffDrawing {
    static func thinLineWidth(_ layout: ScoreLayout) -> CGFloat {
        max(0.9 * layout.zoom, 0.6)
    }

    static func staffLines(from startX: CGFloat, to endX: CGFloat, bottomLineY: CGFloat, layout: ScoreLayout, in context: GraphicsContext) {
        var path = Path()
        for line in 0..<5 {
            let y = layout.y(staffPosition: line * 2, bottomLineY: bottomLineY)
            path.move(to: CGPoint(x: startX, y: y))
            path.addLine(to: CGPoint(x: endX, y: y))
        }
        context.stroke(path, with: .color(Palette.ink), lineWidth: thinLineWidth(layout))
    }
}
