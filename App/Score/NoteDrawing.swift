import MusicMemoCore
import SwiftUI

/// 記譜用に変換した音符（NotatedChord）を描く。寸法は SMuFL の譜線間隔単位（Bravura のメタデータ）。
struct NoteDrawing {
    let layout: ScoreLayout
    let bottomLineY: CGFloat
    let color: Color

    private var space: CGFloat { layout.staffSpace }
    private var stemThickness: CGFloat { max(0.12 * space, 1) }
    private var blackHeadWidth: CGFloat { 1.18 * space }
    private var wholeHeadWidth: CGFloat { 1.688 * space }
    private var stemLength: CGFloat { 3.5 * space }

    private func y(_ position: Int) -> CGFloat {
        layout.y(staffPosition: position, bottomLineY: bottomLineY)
    }

    /// 音符を1つ描く。stemEndY を渡すと符幹をそこまで伸ばし、旗は描かない（連桁でつなぐとき）。
    func draw(_ chord: NotatedChord, stemEndY: CGFloat? = nil, in context: GraphicsContext) {
        let centerX = layout.x(tick: chord.start)
        if chord.isRest {
            drawRest(chord.value, centerX: centerX, in: context)
            return
        }
        let headWidth = chord.value.value == .whole ? wholeHeadWidth : blackHeadWidth
        let headLeft = centerX - headWidth / 2

        drawLedgerLines(chord, headLeft: headLeft, headWidth: headWidth, in: context)

        let glyph: Glyph = switch chord.value.value {
        case .whole: .noteheadWhole
        case .half: .noteheadHalf
        default: .noteheadBlack
        }
        // ずらした符頭は、符幹が上向きなら右、下向きなら左へ
        let displacement = (chord.stemUp ? 1 : -1) * (headWidth - stemThickness)
        for head in chord.heads {
            let left = headLeft + (head.isDisplaced ? displacement : 0)
            SMuFL.draw(glyph, at: CGPoint(x: left, y: y(head.staffPosition)), staffSpace: space, color: color, in: context)
        }

        drawAccidentals(chord, headLeft: headLeft, in: context)
        if chord.value.isDotted {
            drawDots(chord, headRight: headLeft + headWidth + (chord.heads.contains(where: \.isDisplaced) && chord.stemUp ? headWidth : 0), in: context)
        }
        if chord.value.hasStem {
            drawStemAndFlags(chord, headLeft: headLeft, headWidth: headWidth, stemEndY: stemEndY, in: context)
        }
    }

    // MARK: 連桁・タイ・3連符

    private func headWidth(_ chord: NotatedChord) -> CGFloat {
        chord.value.value == .whole ? wholeHeadWidth : blackHeadWidth
    }

    /// 符幹の x。
    private func stemX(_ chord: NotatedChord) -> CGFloat {
        let left = layout.x(tick: chord.start) - headWidth(chord) / 2
        return chord.stemUp ? left + headWidth(chord) - stemThickness / 2 : left + stemThickness / 2
    }

    /// 連桁が無いときの符幹の先端の y。
    private func defaultStemEnd(_ chord: NotatedChord) -> CGFloat {
        let lowest = chord.heads.first?.staffPosition ?? Notation.middleLine
        let highest = chord.heads.last?.staffPosition ?? Notation.middleLine
        let middleY = y(Notation.middleLine)
        return chord.stemUp ? min(y(highest) - stemLength, middleY) : max(y(lowest) + stemLength, middleY)
    }

    /// 連桁でつなぐまとまりを描く（水平の連桁。16分は2本目を足し、孤立した16分は短い連桁）。
    func drawBeamGroup(_ chords: [NotatedChord], in context: GraphicsContext) {
        guard let first = chords.first, let last = chords.last else { return }
        let stemUp = first.stemUp
        let ends = chords.map(defaultStemEnd)
        let beamY = stemUp ? ends.min()! : ends.max()!
        let thickness = 0.5 * space
        let step = 0.75 * space * (stemUp ? 1 : -1)  // 2本目は符頭側へずらす
        let beamTop = { (level: Int) in (stemUp ? beamY : beamY - thickness) + CGFloat(level) * step }

        for chord in chords {
            draw(chord, stemEndY: beamY, in: context)
        }
        context.fill(Path(CGRect(x: stemX(first) - stemThickness / 2, y: beamTop(0),
                                 width: stemX(last) - stemX(first) + stemThickness, height: thickness)),
                     with: .color(color))

        // 2本目（16分）
        for (index, chord) in chords.enumerated() where chord.value.flagCount >= 2 {
            let x = stemX(chord)
            let next = index + 1 < chords.count ? chords[index + 1] : nil
            let previous = index > 0 ? chords[index - 1] : nil
            if let next, next.value.flagCount >= 2 {
                context.fill(Path(CGRect(x: x - stemThickness / 2, y: beamTop(1), width: stemX(next) - x + stemThickness, height: thickness)),
                             with: .color(color))
            } else if previous.map({ $0.value.flagCount >= 2 }) != true {
                // 両隣が8分なら短い連桁（まとまりの最後なら左向き）
                let stub = 1.1 * space
                let left = next == nil ? x - stub : x - stemThickness / 2
                context.fill(Path(CGRect(x: left, y: beamTop(1), width: stub + stemThickness / 2, height: thickness)),
                             with: .color(color))
            }
        }
    }

    /// タイの弧。次の音（end の位置で始まる音）の同じ音高へつなぐ。次が無ければ短く右へ伸ばす。
    func drawTies(_ chord: NotatedChord, next: NotatedChord?, in context: GraphicsContext) {
        let width = headWidth(chord)
        let startX = layout.x(tick: chord.start) + width * 0.45
        for (index, head) in chord.heads.enumerated() where head.tiesToNext {
            let endX: CGFloat
            if let next, next.heads.contains(where: { $0.pitch == head.pitch }) {
                endX = layout.x(tick: next.start) - headWidth(next) * 0.45
            } else {
                endX = startX + 2 * space
            }
            // 符幹と反対側に弧を描く。和音の一番上の音は上向き。
            let above = chord.heads.count > 1 ? index == chord.heads.count - 1 : !chord.stemUp
            let direction: CGFloat = above ? -1 : 1
            let baseY = y(head.staffPosition) + direction * 0.6 * space
            let height = min(max((endX - startX) * 0.12, 0.6 * space), 1.6 * space)
            var tie = Path()
            tie.move(to: CGPoint(x: startX, y: baseY))
            tie.addQuadCurve(to: CGPoint(x: endX, y: baseY), control: CGPoint(x: (startX + endX) / 2, y: baseY + direction * height))
            tie.addQuadCurve(to: CGPoint(x: startX, y: baseY),
                             control: CGPoint(x: (startX + endX) / 2, y: baseY + direction * (height - 0.22 * space)))
            context.fill(tie, with: .color(color))
            context.stroke(tie, with: .color(color), lineWidth: max(0.1 * space, 0.5))
        }
    }

    /// 3連符の「3」。符幹の先の側に置く。
    func drawTuplet(_ chords: [NotatedChord], in context: GraphicsContext) {
        guard let first = chords.first, let last = chords.last else { return }
        let stemUp = chords.filter { !$0.isRest }.first?.stemUp ?? true
        let ends = chords.filter { !$0.isRest && $0.value.hasStem }.map(defaultStemEnd)
        let x = (layout.x(tick: first.start) + layout.x(tick: last.start)) / 2
        let edge = stemUp ? (ends.min() ?? y(10)) - 0.5 * space : (ends.max() ?? y(-2)) + 0.5 * space
        context.draw(
            Text("3").font(.system(size: layout.textSize(11, minimumScale: 0.9), weight: .semibold).italic()).foregroundStyle(color),
            at: CGPoint(x: x, y: edge),
            anchor: stemUp ? .bottom : .top
        )
    }

    private func drawLedgerLines(_ chord: NotatedChord, headLeft: CGFloat, headWidth: CGFloat, in context: GraphicsContext) {
        let extensionWidth = 0.4 * space
        var path = Path()
        for position in chord.ledgerLinePositions {
            path.move(to: CGPoint(x: headLeft - extensionWidth, y: y(position)))
            path.addLine(to: CGPoint(x: headLeft + headWidth + extensionWidth, y: y(position)))
        }
        context.stroke(path, with: .color(color), lineWidth: max(0.16 * space, 1))
    }

    private func drawStemAndFlags(_ chord: NotatedChord, headLeft: CGFloat, headWidth: CGFloat, stemEndY: CGFloat?, in context: GraphicsContext) {
        guard let lowest = chord.heads.first?.staffPosition, let highest = chord.heads.last?.staffPosition else { return }
        let middleY = y(Notation.middleLine)
        let stemX: CGFloat
        let startY: CGFloat
        let endY: CGFloat
        if chord.stemUp {
            // stemUpSE アンカー：符頭の右端、0.168 間隔上
            stemX = headLeft + headWidth - stemThickness / 2
            startY = y(lowest) - 0.168 * space
            endY = min(y(highest) - stemLength, middleY)
        } else {
            // stemDownNW アンカー：符頭の左端、0.168 間隔下
            stemX = headLeft + stemThickness / 2
            startY = y(highest) + 0.168 * space
            endY = max(y(lowest) + stemLength, middleY)
        }
        var stem = Path()
        stem.move(to: CGPoint(x: stemX, y: startY))
        stem.addLine(to: CGPoint(x: stemX, y: stemEndY ?? endY))
        context.stroke(stem, with: .color(color), lineWidth: stemThickness)
        guard stemEndY == nil else { return }

        let flag: Glyph? = switch (chord.value.flagCount, chord.stemUp) {
        case (1, true): .flag8thUp
        case (1, false): .flag8thDown
        case (2, true): .flag16thUp
        case (2, false): .flag16thDown
        default: nil
        }
        if let flag {
            SMuFL.draw(flag, at: CGPoint(x: stemX - stemThickness / 2, y: endY), staffSpace: space, color: color, in: context)
        }
    }

    /// 臨時記号。近い位置（6段以内）に重なるものは左の列へずらす。
    private func drawAccidentals(_ chord: NotatedChord, headLeft: CGFloat, in context: GraphicsContext) {
        var columns: [[Int]] = []
        let leftmostHead = headLeft - (chord.heads.contains(where: \.isDisplaced) && !chord.stemUp ? blackHeadWidth : 0)
        for head in chord.heads.reversed() {
            guard let alter = head.accidental else { continue }
            let column = columns.firstIndex { $0.allSatisfy { abs($0 - head.staffPosition) >= 6 } } ?? columns.count
            if column == columns.count { columns.append([]) }
            columns[column].append(head.staffPosition)

            let glyph: Glyph = switch alter {
            case 1: .accidentalSharp
            case -1: .accidentalFlat
            default: .accidentalNatural
            }
            let x = leftmostHead - (0.3 + 1.1 * CGFloat(column + 1)) * space
            SMuFL.draw(glyph, at: CGPoint(x: x, y: y(head.staffPosition)), staffSpace: space, color: color, in: context)
        }
    }

    /// 付点。線上の符頭なら1つ上の間に置く。
    private func drawDots(_ chord: NotatedChord, headRight: CGFloat, in context: GraphicsContext) {
        let positions = Set(chord.heads.map { $0.staffPosition.isMultiple(of: 2) ? $0.staffPosition + 1 : $0.staffPosition })
        for position in positions {
            SMuFL.draw(.augmentationDot, at: CGPoint(x: headRight + 0.4 * space, y: y(position)), staffSpace: space, color: color, in: context)
        }
    }

    private func drawRest(_ value: NoteDuration, centerX: CGFloat, in context: GraphicsContext) {
        // 全休符は第4線から下がり、2分休符は第3線の上に乗る。それ以外は第3線が基準点。
        let (glyph, position, width): (Glyph, Int, CGFloat) = switch value.value {
        case .whole: (.restWhole, 6, 1.128)
        case .half: (.restHalf, 4, 1.128)
        case .quarter: (.restQuarter, 4, 1.08)
        case .eighth: (.rest8th, 4, 0.988)
        case .sixteenth: (.rest16th, 4, 1.28)
        }
        let left = centerX - width * space / 2
        SMuFL.draw(glyph, at: CGPoint(x: left, y: y(position)), staffSpace: space, color: color, in: context)
        if value.isDotted {
            SMuFL.draw(.augmentationDot, at: CGPoint(x: left + (width + 0.4) * space, y: y(position + 1)), staffSpace: space, color: color, in: context)
        }
    }
}
