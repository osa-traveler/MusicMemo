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

    func draw(_ chord: NotatedChord, in context: GraphicsContext) {
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
            drawStemAndFlags(chord, headLeft: headLeft, headWidth: headWidth, in: context)
        }
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

    private func drawStemAndFlags(_ chord: NotatedChord, headLeft: CGFloat, headWidth: CGFloat, in context: GraphicsContext) {
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
        stem.addLine(to: CGPoint(x: stemX, y: endY))
        context.stroke(stem, with: .color(color), lineWidth: stemThickness)

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
