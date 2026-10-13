import MusicMemoCore
import SwiftUI

/// ルーラ（譜面と一緒に横スクロールする）。目盛りは 小節 ＞ 拍 ＞ 8分 ＞ 16分 の4段階。
/// 編集位置の赤い三角を描き、タップ／ドラッグで編集位置を動かす。
struct RulerView: View {
    let layout: ScoreLayout
    /// 横スクロール量（コンテンツ座標の表示左端）。
    let offset: CGFloat
    let editPosition: Tick
    let onSeek: (Tick) -> Void

    /// 編集位置を動かす単位（16分音符）。
    static let seekGrid = Timing.ticksPerSixteenth

    var body: some View {
        Canvas { context, size in
            // 音部記号の領域（左端に固定）には目盛りを出さない
            context.clip(to: Path(CGRect(x: layout.stickyWidth - 1, y: 0, width: size.width, height: size.height)))
            context.translateBy(x: -offset, y: 0)
            drawTicks(visibleFrom: offset, to: offset + size.width, height: size.height, in: context)
            drawEditMarker(in: context)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    onSeek(layout.tick(atContentX: drag.location.x + offset, grid: Self.seekGrid))
                }
        )
    }

    private func drawTicks(visibleFrom minX: CGFloat, to maxX: CGFloat, height: CGFloat, in context: GraphicsContext) {
        let time = layout.timeSignature
        let firstBar = layout.bar(atContentX: minX)
        let lastBar = layout.bar(atContentX: maxX)
        let sixteenth = Timing.ticksPerSixteenth

        var bars = Path(), beats = Path(), eighths = Path(), sixteenths = Path()
        for bar in firstBar...lastBar {
            let barX = layout.barLineX(bar: bar)
            bars.move(to: CGPoint(x: barX, y: 2))
            bars.addLine(to: CGPoint(x: barX, y: height))
            context.draw(
                Text("\(bar)").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.ink),
                at: CGPoint(x: barX + 4, y: 12),
                anchor: .bottomLeading
            )

            let start = time.startTick(ofBar: bar)
            for tick in stride(from: start, to: start + time.ticksPerBar, by: sixteenth) {
                let x = layout.x(tick: tick)
                let inBeat = (tick - start) % time.ticksPerBeat
                if inBeat == 0 {
                    beats.move(to: CGPoint(x: x, y: 16)); beats.addLine(to: CGPoint(x: x, y: height))
                } else if inBeat % (sixteenth * 2) == 0 {
                    eighths.move(to: CGPoint(x: x, y: 22)); eighths.addLine(to: CGPoint(x: x, y: height))
                } else {
                    sixteenths.move(to: CGPoint(x: x, y: 25)); sixteenths.addLine(to: CGPoint(x: x, y: height))
                }
            }
        }
        context.stroke(sixteenths, with: .color(Palette.ruleStrong), lineWidth: 1)
        context.stroke(eighths, with: .color(Palette.rulerEighth), lineWidth: 1)
        context.stroke(beats, with: .color(Palette.inkSecondary), lineWidth: 1)
        context.stroke(bars, with: .color(Palette.inkSecondary), lineWidth: 1)
    }

    private func drawEditMarker(in context: GraphicsContext) {
        let x = layout.x(tick: editPosition)
        var triangle = Path()
        triangle.move(to: CGPoint(x: x - 7, y: 6))
        triangle.addLine(to: CGPoint(x: x + 7, y: 6))
        triangle.addLine(to: CGPoint(x: x, y: 15))
        triangle.closeSubpath()
        context.fill(triangle, with: .color(Palette.playhead))
    }
}

/// ルーラ左列：「小節 · 拍」と現在位置（7 . 1 . 1）。
struct RulerHeaderView: View {
    let position: BarPosition

    var body: some View {
        HStack {
            Text("小節 · 拍")
                .foregroundStyle(Palette.inkSecondary)
            Spacer()
            Text("\(position.bar) . \(position.beat) . \(position.sixteenth)")
                .fontWeight(.bold)
                .foregroundStyle(Palette.playhead)
                .monospacedDigit()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
    }
}
