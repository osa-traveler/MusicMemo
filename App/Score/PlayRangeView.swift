import MusicMemoCore
import SwiftUI

/// 再生範囲バー（ルーラの上）。始点〜終点を青い帯で示し、両端のつまみのドラッグで範囲を変える（拍単位）。
struct PlayRangeView: View {
    let layout: ScoreLayout
    let offset: CGFloat
    let range: Range<Tick>
    let isLooping: Bool
    let onChange: (_ start: Tick?, _ end: Tick?) -> Void

    private enum Handle { case start, end }
    @State private var dragging: Handle?

    private let handleWidth: CGFloat = 6
    /// つまみを掴める距離。
    private let grabDistance: CGFloat = 22

    var body: some View {
        Canvas { context, size in
            context.clip(to: Path(CGRect(x: layout.stickyWidth - 1, y: 0, width: size.width, height: size.height)))
            context.translateBy(x: -offset, y: 0)
            let startX = layout.boundaryX(tick: range.lowerBound)
            let endX = layout.boundaryX(tick: range.upperBound)

            context.fill(Path(roundedRect: CGRect(x: startX, y: 4, width: endX - startX, height: 11), cornerRadius: 3),
                         with: .color(Palette.accent.opacity(0.28)))
            for x in [startX, endX - handleWidth] {
                context.fill(Path(roundedRect: CGRect(x: x, y: 2, width: handleWidth, height: 15), cornerRadius: 2),
                             with: .color(Palette.accent))
            }
            let label = context.resolve(
                Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.accentDeep)
            )
            let labelSize = label.measure(in: CGSize(width: CGFloat.infinity, height: .infinity))
            if labelSize.width < endX - startX - 20 {
                context.draw(label, at: CGPoint(x: startX + 14, y: 12.5 - label.firstBaseline(in: labelSize)), anchor: .topLeading)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let x = drag.location.x + offset
                    if dragging == nil {
                        dragging = nearestHandle(to: drag.startLocation.x + offset)
                    }
                    let beat = layout.timeSignature.ticksPerBeat
                    switch dragging {
                    case .start: onChange(layout.boundaryTick(atContentX: x, grid: beat), nil)
                    case .end: onChange(nil, layout.boundaryTick(atContentX: x, grid: beat))
                    case nil: break
                    }
                }
                .onEnded { _ in dragging = nil }
        )
    }

    private func nearestHandle(to x: CGFloat) -> Handle? {
        let startDistance = abs(x - layout.boundaryX(tick: range.lowerBound))
        let endDistance = abs(x - layout.boundaryX(tick: range.upperBound))
        guard min(startDistance, endDistance) <= grabDistance else { return nil }
        return startDistance <= endDistance ? .start : .end
    }

    /// 「ループ 6–7小節」。両端が小節頭なら小節で、そうでなければ 小節.拍 で表す。
    private var label: String {
        let time = layout.timeSignature
        let start = time.position(of: range.lowerBound)
        let end = time.position(of: range.upperBound)
        let span: String
        if range.lowerBound % time.ticksPerBar == 0, range.upperBound % time.ticksPerBar == 0 {
            let lastBar = end.bar - 1
            span = start.bar == lastBar ? "\(start.bar)小節" : "\(start.bar)–\(lastBar)小節"
        } else {
            span = "\(start.barBeatDescription)–\(end.barBeatDescription)"
        }
        return isLooping ? "ループ \(span)" : span
    }
}

/// 再生範囲バーの左列：「再生範囲 6.1 → 8.1」。
struct PlayRangeHeaderView: View {
    let range: Range<Tick>
    let timeSignature: TimeSignature

    var body: some View {
        HStack {
            Text("再生範囲")
                .foregroundStyle(Palette.inkSecondary)
            Spacer()
            Text("\(timeSignature.position(of: range.lowerBound).barBeatDescription) → \(timeSignature.position(of: range.upperBound).barBeatDescription)")
                .fontWeight(.bold)
                .foregroundStyle(Palette.accent)
                .monospacedDigit()
        }
        .font(.system(size: 10))
        .padding(.horizontal, 12)
    }
}
