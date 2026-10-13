import MusicMemoCore
import SwiftUI

/// 音価（3×3）。1・2行目：全音符・2分・4分・8分・16分・付点、3行目（薄い地色）：4分休符・タイ・3連符。
/// 付点・3連符・タイは音価に重ねる修飾。休符は押すとすぐ入力する。
struct DurationPadView: View {
    let store: SketchStore
    var onRest: () -> Void = {}

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        let duration = store.editor.duration
        VStack(alignment: .leading, spacing: 8) {
            PaletteHeading("音価")
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach([NoteValue.whole, .half, .quarter, .eighth, .sixteenth], id: \.self) { value in
                    padButton(.note(value), label: value.label, isOn: duration.value == value) {
                        store.selectNoteValue(value)
                    }
                }
                padButton(.dotted, label: "付点", isOn: duration.isDotted) { store.toggleDotted() }
                padButton(.rest, label: "休符", isOn: false, muted: true, action: onRest)
                padButton(.tie, label: "タイ", isOn: store.editor.isTieOn, muted: true) { store.toggleTie() }
                padButton(.triplet, label: "3連符", isOn: duration.isTriplet, muted: true) { store.toggleTriplet() }
            }
        }
    }

    private func padButton(_ icon: DurationIcon.Kind, label: String, isOn: Bool, muted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DurationIcon(kind: icon, color: isOn ? Palette.paper : Palette.ink, isOn: isOn)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isOn ? Palette.accent : muted ? Palette.paperMuted : Palette.paper, in: .rect(cornerRadius: 10))
                .overlay {
                    if !isOn { RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.rule, lineWidth: 1) }
                }
                .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension NoteValue {
    var label: String {
        switch self {
        case .whole: "全音符"
        case .half: "2分音符"
        case .quarter: "4分音符"
        case .eighth: "8分音符"
        case .sixteenth: "16分音符"
        }
    }
}

/// 音価ボタンの絵（ベクター）。符頭・旗・休符は Bravura、符幹・弧・連桁は線で描く。
struct DurationIcon: View {
    enum Kind {
        case note(NoteValue)
        case dotted
        case rest
        case tie
        case triplet
    }

    let kind: Kind
    let color: Color
    let isOn: Bool

    /// アイコンの譜線間隔。
    private let space: CGFloat = 6.5

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            switch kind {
            case .note(.whole):
                // 全音符は符幹が無いぶん大きめに
                let big = space * 1.4
                SMuFL.draw(.noteheadWhole, at: CGPoint(x: center.x - 0.844 * big, y: center.y), staffSpace: big, color: color, in: context)
            case .note(let value):
                drawNote(value, centerX: center.x, headY: center.y + 1.6 * space, color: color, in: context)
            case .dotted:
                // 薄い音符＋濃い点
                let faded = isOn ? color.opacity(0.55) : Palette.inkTertiary
                drawNote(.quarter, centerX: center.x - 0.4 * space, headY: center.y + 1.6 * space, color: faded, in: context)
                SMuFL.draw(.augmentationDot, at: CGPoint(x: center.x + 0.7 * space, y: center.y + 1.6 * space),
                           staffSpace: space * 1.3, color: color, in: context)
            case .rest:
                let big = space * 1.35
                SMuFL.draw(.restQuarter, at: CGPoint(x: center.x - 0.54 * big, y: center.y), staffSpace: big, color: color, in: context)
            case .tie:
                // 弧で繋いだ2音
                let headY = center.y - 0.3 * space
                for dx in [-1.3 * space, 1.3 * space] {
                    SMuFL.draw(.noteheadBlack, at: CGPoint(x: center.x + dx - 0.59 * space, y: headY), staffSpace: space, color: color, in: context)
                }
                var arc = Path()
                arc.move(to: CGPoint(x: center.x - 1.1 * space, y: headY + 0.8 * space))
                arc.addQuadCurve(to: CGPoint(x: center.x + 1.1 * space, y: headY + 0.8 * space),
                                 control: CGPoint(x: center.x, y: headY + 2 * space))
                context.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            case .triplet:
                drawTriplet(center: center, in: context)
            }
        }
        .frame(width: 44, height: 40)
    }

    /// 符幹上向きの音符。headY は符頭の中心。
    private func drawNote(_ value: NoteValue, centerX: CGFloat, headY: CGFloat, color: Color, in context: GraphicsContext) {
        let headWidth: CGFloat = (value == .whole ? 1.688 : 1.18) * space
        let left = centerX - headWidth / 2
        let head: Glyph = switch value {
        case .whole: .noteheadWhole
        case .half: .noteheadHalf
        default: .noteheadBlack
        }
        let y = value == .whole ? headY - 1.6 * space + space * 0.2 : headY
        SMuFL.draw(head, at: CGPoint(x: left, y: y), staffSpace: space, color: color, in: context)
        guard value != .whole else { return }

        let thickness: CGFloat = 1.4
        let stemX = left + headWidth - thickness / 2
        let top = headY - 3.3 * space
        var stem = Path()
        stem.move(to: CGPoint(x: stemX, y: headY - 0.17 * space))
        stem.addLine(to: CGPoint(x: stemX, y: top))
        context.stroke(stem, with: .color(color), lineWidth: thickness)

        let flag: Glyph? = switch value {
        case .eighth: .flag8thUp
        case .sixteenth: .flag16thUp
        default: nil
        }
        if let flag {
            SMuFL.draw(flag, at: CGPoint(x: stemX - thickness / 2, y: top), staffSpace: space, color: color, in: context)
        }
    }

    /// 連桁でつないだ3つの8分音符と「3」。
    private func drawTriplet(center: CGPoint, in context: GraphicsContext) {
        let small = space * 0.8
        let headY = center.y + 1.5 * small
        let top = headY - 3 * small
        let step = 1.7 * small
        var stems = Path()
        for index in -1...1 {
            let left = center.x + CGFloat(index) * step - 0.59 * small
            SMuFL.draw(.noteheadBlack, at: CGPoint(x: left, y: headY), staffSpace: small, color: color, in: context)
            let stemX = left + 1.18 * small - 0.6
            stems.move(to: CGPoint(x: stemX, y: headY - 0.17 * small))
            stems.addLine(to: CGPoint(x: stemX, y: top))
        }
        context.stroke(stems, with: .color(color), lineWidth: 1.2)
        let beamLeft = center.x - step + 0.59 * small - 1.2
        let beamRight = center.x + step + 0.59 * small
        context.fill(Path(CGRect(x: beamLeft, y: top, width: beamRight - beamLeft, height: 0.5 * small)), with: .color(color))
        context.draw(Text("3").font(.system(size: 8, weight: .bold)).foregroundStyle(color),
                     at: CGPoint(x: center.x + 0.3 * small, y: top - 2), anchor: .bottom)
    }
}
