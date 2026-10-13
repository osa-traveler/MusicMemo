import MusicMemoCore
import SwiftUI

/// 譜面ビュー。全トラックを縦に並べ、各トラックを改行しない横一行の五線で表示する。
/// 左にトラック情報列（固定）、右に縦スクロール列。全トラックは同じ横位置でスクロールする。
struct ScoreView: View {
    @Bindable var store: SketchStore
    @State private var verticalPosition = ScrollPosition()
    @State private var vertical = VerticalMetrics()

    private struct VerticalMetrics: Equatable {
        var offset: CGFloat = 0
        var contentHeight: CGFloat = 0
        var visibleHeight: CGFloat = 0
    }
    var body: some View {
        let layout = store.layout
        let horizontalOffset = store.horizontalOffset
        VStack(spacing: 0) {
            headerRow(height: Metrics.playRangeBarHeight) {
                PlayRangeHeaderView(range: store.sketch.playRange, timeSignature: store.sketch.timeSignature)
            } content: {
                PlayRangeView(layout: layout, offset: horizontalOffset, range: store.sketch.playRange, isLooping: store.sketch.isLooping) {
                    store.setPlayRange(start: $0, end: $1)
                }
            }

            headerRow(height: Metrics.rulerHeight) {
                RulerHeaderView(position: store.sketch.timeSignature.position(of: store.editor.editPosition))
            } content: {
                RulerView(layout: layout, offset: horizontalOffset, editPosition: store.editor.editPosition) {
                    store.setEditPosition($0)
                }
            }
            .overlay(alignment: .bottom) { Palette.rule.frame(height: 1) }

            GeometryReader { geometry in
                let rowHeight = rowHeight(available: geometry.size.height, layout: layout)
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        trackHeaders(rowHeight: rowHeight)
                        staffRows(layout: layout, rowHeight: rowHeight)
                    }
                }
                .scrollIndicators(.hidden)
                .scrollPosition($verticalPosition)
                .onScrollGeometryChange(for: VerticalMetrics.self) { geometry in
                    VerticalMetrics(
                        offset: geometry.contentOffset.y + geometry.contentInsets.top,
                        contentHeight: geometry.contentSize.height,
                        visibleHeight: geometry.containerSize.height
                    )
                } action: { _, metrics in
                    vertical = metrics
                }
            }
        }
        .overlay { positionLines(layout: layout) }
        .padding(.trailing, Metrics.verticalScrollbarWidth)
        .overlay(alignment: .trailing) {
            VerticalScrollbar(offset: vertical.offset, contentHeight: vertical.contentHeight, visibleHeight: vertical.visibleHeight) {
                verticalPosition.scrollTo(y: $0)
            }
            .padding(.vertical, 6)
            .padding(.trailing, 4)
        }
    }

    /// 再生範囲バー・ルーラの1段（左にトラック情報列と同じ幅の見出し）。
    private func headerRow(height: CGFloat, @ViewBuilder header: () -> some View, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 0) {
            header()
                .frame(width: Metrics.trackHeaderWidth, height: height)
                .overlay(alignment: .trailing) { Palette.rule.frame(width: 1) }
            content()
        }
        .frame(height: height)
        .background(Palette.paperMuted)
    }

    /// 再生範囲の青い点線（ルーラから全トラックを貫く）と、赤い編集位置ライン（ルーラの三角の下から最下部まで）。
    /// 音部記号の領域に入ったら隠す。
    private func positionLines(layout: ScoreLayout) -> some View {
        Canvas { context, size in
            let visible = { (x: CGFloat) in x >= layout.stickyWidth - 1 && x <= size.width }

            let rulerTop = Metrics.playRangeBarHeight
            var dashes = Path()
            for tick in [store.sketch.playRange.lowerBound, store.sketch.playRange.upperBound] {
                let x = layout.boundaryX(tick: tick) - store.horizontalOffset
                guard visible(x) else { continue }
                dashes.move(to: CGPoint(x: x + 0.5, y: rulerTop))
                dashes.addLine(to: CGPoint(x: x + 0.5, y: size.height))
            }
            context.stroke(dashes, with: .color(Palette.accent.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            let x = layout.x(tick: store.editor.editPosition) - store.horizontalOffset
            guard visible(x) else { return }
            let top = rulerTop + 14
            context.fill(Path(CGRect(x: x - 1, y: top, width: 2, height: size.height - top)), with: .color(Palette.playhead))
        }
        .padding(.leading, Metrics.trackHeaderWidth)
        .allowsHitTesting(false)
    }

    /// 編集位置の小節が左から3小節目に来るように横スクロールする（基準画面：7小節目を 5〜8 の中で表示）。
    private func scrollToEditPosition() {
        let leadingBar = max(store.editPositionBar - 2, 1)
        guard leadingBar > 1 else { return }
        store.scroll(toLeadingBar: leadingBar)
    }

    /// トラックが少ないときは行を伸ばして譜面ビューを埋める。
    private func rowHeight(available: CGFloat, layout: ScoreLayout) -> CGFloat {
        let count = max(store.sketch.tracks.count, 1)
        return max(layout.minimumRowHeight, (available / CGFloat(count)).rounded(.down))
    }

    private func trackHeaders(rowHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(store.sketch.tracks) { track in
                TrackHeaderView(
                    track: track,
                    isSelected: store.editor.selectedTrackID == track.id,
                    volume: Binding(get: { track.volume }, set: { store.setVolume($0, of: track.id) }),
                    pan: Binding(get: { track.pan }, set: { store.setPan($0, of: track.id) })
                )
                .frame(height: rowHeight)
                .overlay(alignment: .bottom) { Palette.ruleSoft.frame(height: 1) }
                .onTapGesture { store.selectTrack(track.id) }
            }
        }
    }

    private func staffRows(layout: ScoreLayout, rowHeight: CGFloat) -> some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                ForEach(store.sketch.tracks) { track in
                    StaffRowView(track: track, sketch: store.sketch, editor: store.editor, layout: layout, rowHeight: rowHeight)
                        .overlay(alignment: .bottom) { Palette.ruleSoft.frame(height: 1) }
                        .onTapGesture { location in
                            // 鍵盤入力中は、タップしたトラックを選び、編集位置もそこへ動かす
                            store.selectTrack(track.id)
                            store.setEditPosition(layout.tick(atContentX: location.x, grid: RulerView.seekGrid))
                        }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollPosition($store.horizontalPosition)
        .onAppear { scrollToEditPosition() }
        .onScrollGeometryChange(for: CGRect.self) { geometry in
            geometry.visibleRect
        } action: { _, visible in
            store.horizontalOffset = visible.minX
            store.visibleStaffWidth = visible.width
        }
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(Array(store.sketch.tracks.enumerated()), id: \.element.id) { index, track in
                    StickyClefView(
                        track: track,
                        layout: layout,
                        rowHeight: rowHeight,
                        leadingBarNumber: index == 0 ? layout.bar(atContentX: store.horizontalOffset + layout.stickyWidth + 1) : nil
                    )
                    .overlay(alignment: .bottom) { Palette.ruleSoft.frame(height: 1) }
                }
            }
            .allowsHitTesting(false)
        }
    }
}
