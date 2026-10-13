import MusicMemoCore
import SwiftUI

/// 全体ビュー。曲全体の小節をカードで並べ、譜面ビューの横スクロールバーとして働く。
/// 青い枠＝譜面に見えている範囲。枠のドラッグでスクロール、カードのタップでその小節へ。
/// カードは最小幅まで縮め、それでも収まらなければ全体ビュー自体が枠に追従して横にずれる。
struct OverviewView: View {
    let store: SketchStore

    static let cardGap: CGFloat = 4
    static let minCardWidth: CGFloat = 40
    /// 枠を全体ビューの端からこれ以上近づけない（自動で追従するとき）。
    static let followMargin: CGFloat = 12

    @State private var width: CGFloat = 0
    /// 全体ビュー自体の横スクロール量（カードが収まらないときだけ使う）。
    @State private var scrollX: CGFloat = 0
    /// 枠のドラッグ開始時の譜面スクロール量。枠の外から始めたドラッグは nil のまま無視する。
    @State private var dragStartOffset: CGFloat?
    @State private var isDraggingFrame = false

    private var barCount: Int { store.sketch.barCount }

    private var cardWidth: CGFloat {
        guard barCount > 0, width > 0 else { return Self.minCardWidth }
        let fitted = (width - Self.cardGap * CGFloat(barCount - 1)) / CGFloat(barCount)
        return max(fitted, Self.minCardWidth)
    }

    private var pitch: CGFloat { cardWidth + Self.cardGap }
    private var totalWidth: CGFloat { pitch * CGFloat(barCount) - Self.cardGap }

    /// 譜面に見えている範囲（小節単位、0始まりの小数）。
    private var visibleBarSpan: (start: CGFloat, end: CGFloat) {
        let layout = store.layout
        let toBars = { (x: CGFloat) in min(max((x - layout.contentLeading) / layout.barWidth, 0), CGFloat(barCount)) }
        let start = toBars(store.horizontalOffset + layout.stickyWidth)
        let end = toBars(store.horizontalOffset + store.visibleStaffWidth)
        return (start, max(start, end))
    }

    /// 枠の左端・右端（全体ビューのコンテンツ座標）。カードの外側に少しはみ出す。
    private var frameRange: (minX: CGFloat, maxX: CGFloat) {
        let span = visibleBarSpan
        return (span.start * pitch - 3, span.end * pitch - Self.cardGap + 3)
    }

    var body: some View {
        // カード列は全体ビューより広くなりうるので、overlay に置いてレイアウトの大きさに影響させない
        Color.clear
            .overlay(alignment: .topLeading) { content }
            .contentShape(Rectangle())
            .gesture(frameDrag)
            // 横は全体ビューの幅で切り、縦は枠のはみ出し分を残す
            .mask(Rectangle().padding(.vertical, -6))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onChange(of: frameRange.minX) { followFrame() }
            .onChange(of: width) { followFrame() }
    }

    private var content: some View {
        let frame = frameRange
        return VStack(alignment: .leading, spacing: 6) {
            sectionLabels
                .frame(height: 14)
            ZStack(alignment: .topLeading) {
                cards
                ViewportFrame()
                    .frame(width: max(frame.maxX - frame.minX, 12), height: Metrics.overviewCardHeight + 8)
                    .offset(x: frame.minX, y: -4)
                    .allowsHitTesting(false)
            }
            .frame(height: Metrics.overviewCardHeight)
        }
        .fixedSize()
        .offset(x: -scrollX)
    }

    // MARK: セクション名

    /// セクション名。セクションの頭が左に隠れているときは、全体ビューの左端に貼り付ける。
    private var sectionLabels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(store.sketch.sections) { section in
                let isCurrent = store.currentSection?.id == section.id
                let start = pitch * CGFloat(section.startBar - 1)
                let end = start + pitch * CGFloat(section.barCount) - Self.cardGap
                let left = min(max(start, scrollX), end)
                Text(section.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                    .padding(.leading, 6)
                    .frame(width: max(end - left, 0), alignment: .leading)
                    .clipped()
                    .overlay(alignment: .leading) {
                        (isCurrent ? Palette.ink : Palette.ruleStrong).frame(width: 2)
                    }
                    .offset(x: left)
            }
        }
    }

    // MARK: 小節カード

    private var cards: some View {
        let sketch = store.sketch
        let time = sketch.timeSignature
        let selectedTrack = sketch.tracks.first { $0.id == store.editor.selectedTrackID }
        let notesByBar = Dictionary(grouping: selectedTrack?.notes ?? []) { time.bar(containing: $0.start) }
        let barsWithNotes = Set(sketch.tracks.flatMap { $0.notes.map { time.bar(containing: $0.start) } })
        let editBar = store.editPositionBar

        return HStack(spacing: Self.cardGap) {
            ForEach(1...max(barCount, 1), id: \.self) { bar in
                let chords = sketch.chords(inBar: bar).map(\.chord.symbol)
                OverviewCard(
                    chordLabel: chords.joined(separator: " "),
                    notes: notesByBar[bar] ?? [],
                    barStart: time.startTick(ofBar: bar),
                    ticksPerBar: time.ticksPerBar,
                    clef: selectedTrack?.clef ?? .treble,
                    key: sketch.key,
                    isEmpty: chords.isEmpty && !barsWithNotes.contains(bar),
                    isEditing: bar == editBar
                )
                .frame(width: cardWidth, height: Metrics.overviewCardHeight)
                .onTapGesture { store.select(bar: bar) }
            }
        }
    }

    // MARK: 操作

    /// 枠の中から始めたドラッグで譜面を横スクロールする。
    private var frameDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { drag in
                if !isDraggingFrame {
                    isDraggingFrame = true
                    let x = drag.startLocation.x + scrollX
                    let frame = frameRange
                    dragStartOffset = (frame.minX - 10...frame.maxX + 10).contains(x) ? store.horizontalOffset : nil
                }
                guard let start = dragStartOffset else { return }
                let barsMoved = drag.translation.width / pitch
                store.scrollStaff(toOffset: start + barsMoved * store.layout.barWidth)
            }
            .onEnded { _ in
                isDraggingFrame = false
                dragStartOffset = nil
            }
    }

    /// カードが収まらないとき、枠が見える位置まで全体ビューをずらす。
    private func followFrame() {
        let maxScroll = max(totalWidth - width, 0)
        guard maxScroll > 0 else {
            scrollX = 0
            return
        }
        let frame = frameRange
        var target = scrollX
        if frame.minX < target + Self.followMargin {
            target = frame.minX - Self.followMargin
        } else if frame.maxX > target + width - Self.followMargin {
            target = frame.maxX - width + Self.followMargin
        }
        scrollX = min(max(target, 0), maxScroll)
    }
}

/// 表示範囲の枠（青い2ptの枠＋両端のつまみ）。つまみでの幅変更（ズーム）は Step 5。
private struct ViewportFrame: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 11)
            .fill(Palette.accent.opacity(0.06))
            .strokeBorder(Palette.accent, lineWidth: 2)
            .overlay {
                HStack {
                    handle.offset(x: -4)
                    Spacer()
                    handle.offset(x: 4)
                }
            }
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Palette.accent)
            .frame(width: 6, height: 22)
    }
}

/// 小節カード（1小節＝1枚）。コード名＋小さな五線（選択中トラックの音符を点で示す）。
private struct OverviewCard: View {
    let chordLabel: String
    let notes: [Note]
    let barStart: Tick
    let ticksPerBar: Tick
    let clef: Clef
    let key: Key
    let isEmpty: Bool
    let isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(isEmpty || chordLabel.isEmpty ? "—" : chordLabel)
                    .font(.system(size: 11, weight: isEmpty ? .regular : .bold))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                if isEditing {
                    Circle().fill(Palette.accent).frame(width: 6, height: 6)
                }
            }
            .frame(height: 13)
            miniStaff
                .frame(height: 17)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isEmpty ? Palette.ruleStrong : Palette.rule,
                              style: StrokeStyle(lineWidth: 1, dash: isEmpty ? [3, 2] : []))
        }
        .contentShape(.rect(cornerRadius: 8))
    }

    private var labelColor: Color {
        if isEmpty || chordLabel.isEmpty { return Palette.inkTertiary }
        return isEditing ? Palette.accent : Palette.chord
    }

    private var background: Color {
        if isEditing { return Palette.accentTint }
        return isEmpty ? Palette.cardEmpty : Palette.paper
    }

    /// 線の間隔4ptの五線。音符は高さと拍の位置に合わせた点。
    private var miniStaff: some View {
        Canvas { context, size in
            var lines = Path()
            for index in 0..<5 {
                let y = 0.5 + CGFloat(index) * 4
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(lines, with: .color(isEmpty ? Palette.rule : Palette.ruleStrong), lineWidth: 1)

            let dotSize: CGFloat = 3.5
            for note in notes {
                guard let pitch = note.pitch else { continue }
                let position = clef.staffPosition(of: SpelledPitch(pitch, in: key))
                let y = min(max(16.5 - CGFloat(position) * 2, 0), size.height)
                let fraction = CGFloat(note.start - barStart) / CGFloat(ticksPerBar)
                let x = 2 + fraction * (size.width - 4 - dotSize)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y - dotSize / 2, width: dotSize, height: dotSize)),
                             with: .color(isEditing ? Palette.accent : Palette.ink))
            }
        }
    }
}
