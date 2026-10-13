import MusicMemoCore
import SwiftUI

/// 1トラック分の五線（横スクロールするコンテンツ）。小節線・拍子記号・音符を描く。
struct StaffRowView: View {
    let track: Track
    let sketch: Sketch
    let editor: EditorState
    let layout: ScoreLayout
    let rowHeight: CGFloat

    private var isSelected: Bool { editor.selectedTrackID == track.id }

    var body: some View {
        let chords = Notation.chords(for: track.notes, clef: track.clef, key: sketch.key, timeSignature: layout.timeSignature)
        Canvas { context, size in
            let bottom = layout.bottomLineY(rowHeight: size.height)
            if isSelected {
                drawInputBar(rowHeight: size.height, in: context)
            }
            StaffDrawing.staffLines(from: 0, to: size.width, bottomLineY: bottom, layout: layout, in: context)
            drawBarLines(bottomLineY: bottom, in: context)
            drawTimeSignature(bottomLineY: bottom, in: context)
            if track.showsChordSymbols {
                drawChordSymbols(bottomLineY: bottom, in: context)
            }
            let notes = NoteDrawing(layout: layout, bottomLineY: bottom, color: Palette.ink)
            for chord in chords {
                notes.draw(chord, in: context)
            }
            if isSelected {
                drawPreviewNote(bottomLineY: bottom, in: context)
            }
        }
        .frame(width: layout.contentWidth, height: rowHeight)
    }

    /// 入力中の小節（編集位置の小節）を薄い青で塗る。
    private func drawInputBar(rowHeight: CGFloat, in context: GraphicsContext) {
        let bar = layout.timeSignature.bar(containing: editor.editPosition)
        let rect = layout.inputBarRect(bar: bar, rowHeight: rowHeight)
        context.fill(Path(roundedRect: rect, cornerRadius: 6 * layout.zoom), with: .color(Palette.accent.opacity(0.08)))
    }

    /// コードトラックの五線の上にコードネーム（オレンジ）。
    private func drawChordSymbols(bottomLineY: CGFloat, in context: GraphicsContext) {
        let baselineY = layout.y(staffPosition: 8, bottomLineY: bottomLineY) - layout.chordSymbolOffset
        for event in sketch.chords {
            let text = context.resolve(
                Text(event.chord.symbol)
                    .font(.system(size: 15 * layout.zoom, weight: .bold))
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

    private func drawBarLines(bottomLineY: CGFloat, in context: GraphicsContext) {
        let top = layout.y(staffPosition: 8, bottomLineY: bottomLineY)
        var path = Path()
        for bar in 1...(layout.barCount + 1) {
            let x = layout.barLineX(bar: bar)
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
                    Text("\(leadingBarNumber)").font(.system(size: 10 * layout.zoom)).foregroundStyle(Palette.inkTertiary),
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
