import MusicMemoCore
import SwiftUI

/// 1トラック分の五線（横スクロールするコンテンツ）。小節線・拍子記号を描く。
struct StaffRowView: View {
    let track: Track
    let layout: ScoreLayout
    let rowHeight: CGFloat

    var body: some View {
        Canvas { context, size in
            let bottom = layout.bottomLineY(rowHeight: size.height)
            StaffDrawing.staffLines(from: 0, to: size.width, bottomLineY: bottom, layout: layout, in: context)
            drawBarLines(bottomLineY: bottom, in: context)
            drawTimeSignature(bottomLineY: bottom, in: context)
        }
        .frame(width: layout.contentWidth, height: rowHeight)
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
