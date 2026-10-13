import MusicMemoCore
import SwiftUI

/// 譜面ビュー。全トラックを縦に並べ、各トラックを改行しない横一行の五線で表示する。
/// 左にトラック情報列（固定）、右に縦スクロール列。全トラックは同じ横位置でスクロールする。
struct ScoreView: View {
    @Bindable var store: SketchStore
    @State private var verticalPosition = ScrollPosition()
    @State private var vertical = VerticalMetrics()

    @State private var rowsAreaHeight: CGFloat = 0
    @State private var pinch: ZoomAnchor?
    @State private var isHUDVisible = false
    @State private var hudToken = 0
    @State private var didInitialScroll = false

    private struct VerticalMetrics: Equatable {
        var offset: CGFloat = 0
        var contentHeight: CGFloat = 0
        var visibleHeight: CGFloat = 0
    }

    /// ズームの基準：開始時の倍率と、指（マウス）の下にあった内容の位置。
    private struct ZoomAnchor {
        var zoom: Double
        var anchorX: CGFloat
        var contentX: CGFloat
        var anchorY: CGFloat
        var contentY: CGFloat
        var rowHeight: CGFloat
    }

    /// 再生範囲バー＋ルーラの高さ（倍率によらず一定）。
    private var headerHeight: CGFloat { Metrics.playRangeBarHeight + Metrics.rulerHeight }

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
                let rowHeight = rowHeight(available: geometry.size.height, zoom: store.editor.zoom)
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
                    // 半分以上見えているトラックを数える
                    let row = self.rowHeight(available: metrics.visibleHeight, zoom: store.editor.zoom)
                    store.visibleTrackCount = min(Int((metrics.visibleHeight / row + 0.5).rounded(.down)), store.sketch.tracks.count)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsAreaHeight = $0 }
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
        .overlay(alignment: .top) {
            if isHUDVisible {
                ZoomHUD(zoom: store.editor.zoom,
                        onZoomOut: { store.stepZoom(-1) },
                        onZoomIn: { store.stepZoom(1) },
                        onReset: { store.setZoom(1) })
                    .padding(.top, 42)
                    .transition(.opacity)
            }
        }
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let anchor = pinch ?? zoomAnchor(at: value.startLocation)
                    pinch = anchor
                    applyZoom(anchor.zoom * value.magnification, from: anchor)
                }
                .onEnded { _ in pinch = nil }
        )
        .commandScrollZoom { factor, location in
            applyZoom(store.editor.zoom * factor, from: zoomAnchor(at: location))
        }
        .onChange(of: store.editor.zoom) {
            withAnimation(.easeOut(duration: 0.15)) { isHUDVisible = true }
            hudToken += 1
        }
        .task(id: hudToken) {
            guard hudToken > 0 else { return }
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled, pinch == nil else { return }
            withAnimation(.easeOut(duration: 0.3)) { isHUDVisible = false }
        }
    }

    // MARK: ズーム

    /// location（譜面ビューの座標）にある内容を基準にする。トラック情報列や見出しの上なら、譜面部分の端を基準にする。
    private func zoomAnchor(at location: CGPoint) -> ZoomAnchor {
        let anchorX = max(location.x - Metrics.trackHeaderWidth, 0)
        let anchorY = max(location.y - headerHeight, 0)
        return ZoomAnchor(
            zoom: store.editor.zoom,
            anchorX: anchorX,
            contentX: store.horizontalOffset + anchorX,
            anchorY: anchorY,
            contentY: vertical.offset + anchorY,
            rowHeight: rowHeight(available: rowsAreaHeight, zoom: store.editor.zoom)
        )
    }

    /// 倍率を変え、基準の内容が同じ場所に残るよう縦横のスクロールを補正する。
    private func applyZoom(_ zoom: Double, from anchor: ZoomAnchor) {
        store.setZoom(zoom, anchorX: anchor.anchorX, contentX: anchor.contentX, baseZoom: anchor.zoom)
        let newRowHeight = rowHeight(available: rowsAreaHeight, zoom: store.editor.zoom)
        let maxY = max(newRowHeight * CGFloat(store.sketch.tracks.count) - rowsAreaHeight, 0)
        let targetY = anchor.contentY * newRowHeight / max(anchor.rowHeight, 1) - anchor.anchorY
        verticalPosition.scrollTo(y: min(max(targetY, 0), maxY))
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

    /// 編集位置の小節が、見える小節数の6割ほどの位置に来るように横スクロールする
    /// （基準画面：100%で 5〜8 の中に7小節目）。譜面の幅が決まってから一度だけ行う。
    private func scrollToEditPosition() {
        let layout = store.layout
        let visibleCount = Int((store.visibleStaffWidth - layout.stickyWidth) / layout.barWidth)
        let leadingBar = max(store.editPositionBar - Int((Double(max(visibleCount, 1)) * 0.6).rounded()), 1)
        guard leadingBar > 1 else { return }
        store.scroll(toLeadingBar: leadingBar)
    }

    private var headerDensity: TrackHeaderView.Density {
        headerDensity(zoom: store.editor.zoom)
    }

    private func headerDensity(zoom: Double) -> TrackHeaderView.Density {
        let layout = store.layout(zoom: zoom)
        if layout.isMinimal { return .minimal }
        if layout.isCompact { return .compact }
        return layout.showsDetail ? .detailed : .regular
    }

    /// 行の高さ。五線に必要な高さとトラック情報が収まる高さの大きい方。
    /// トラックが少ないときは譜面ビューを埋めるよう伸ばすが、縮小時に行間が空きすぎないよう五線の高さの1.1倍までにする。
    private func rowHeight(available: CGFloat, zoom: Double) -> CGFloat {
        let count = max(store.sketch.tracks.count, 1)
        let staffHeight = store.layout(zoom: zoom).minimumRowHeight
        let filled = min((available / CGFloat(count)).rounded(.down), staffHeight * 1.1)
        return max(staffHeight, filled, headerDensity(zoom: zoom).minimumRowHeight)
    }

    private func trackHeaders(rowHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(store.sketch.tracks) { track in
                TrackHeaderView(
                    track: track,
                    isSelected: store.editor.selectedTrackID == track.id,
                    density: headerDensity,
                    volume: Binding(get: { track.volume }, set: { store.setVolume($0, of: track.id) }),
                    pan: Binding(get: { track.pan }, set: { store.setPan($0, of: track.id) }),
                    onToggleMute: { store.toggleMute(of: track.id) },
                    onToggleSolo: { store.toggleSolo(of: track.id) }
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
        .onScrollGeometryChange(for: CGRect.self) { geometry in
            geometry.visibleRect
        } action: { _, visible in
            store.horizontalOffset = visible.minX
            store.visibleStaffWidth = visible.width
            if !didInitialScroll, visible.width > 0 {
                didInitialScroll = true
                scrollToEditPosition()
            }
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
