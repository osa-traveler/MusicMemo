import MusicMemoCore
import SwiftUI

/// 譜面ビュー。全トラックを縦に並べ、各トラックを改行しない横一行の五線で表示する。
/// 左にトラック情報列（固定）、右に縦スクロール列。全トラックは同じ横位置でスクロールする。
struct ScoreView: View {
    @Bindable var store: SketchStore
    @State private var horizontalOffset: CGFloat = 0
    @State private var horizontalPosition = ScrollPosition()

    private var layout: ScoreLayout {
        ScoreLayout(
            zoom: store.editor.zoom,
            timeSignature: store.sketch.timeSignature,
            keySignature: KeySignature(store.sketch.key),
            barCount: store.sketch.barCount
        )
    }

    var body: some View {
        let layout = layout
        VStack(spacing: 0) {
            // 再生範囲バー＋ルーラ（Step 3）の場所
            HStack(spacing: 0) {
                Palette.paperMuted
                    .frame(width: Metrics.trackHeaderWidth)
                    .overlay(alignment: .trailing) { Palette.rule.frame(width: 1) }
                Color.clear
            }
            .frame(height: Metrics.playRangeBarHeight + Metrics.rulerHeight)
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
            }
        }
        .padding(.trailing, Metrics.verticalScrollbarWidth)
    }

    /// 編集位置の小節が左から3小節目に来るように横スクロールする（基準画面：7小節目を 5〜8 の中で表示）。
    private func scrollToEditPosition(layout: ScoreLayout) {
        let editBar = store.sketch.timeSignature.bar(containing: store.editor.editPosition)
        let leadingBar = max(editBar - 2, 1)
        guard leadingBar > 1 else { return }
        horizontalPosition.scrollTo(x: layout.barLineX(bar: leadingBar) - layout.stickyWidth)
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
                    StaffRowView(track: track, layout: layout, rowHeight: rowHeight)
                        .overlay(alignment: .bottom) { Palette.ruleSoft.frame(height: 1) }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollPosition($horizontalPosition)
        .onAppear { scrollToEditPosition(layout: layout) }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.x + geometry.contentInsets.leading
        } action: { _, offset in
            horizontalOffset = offset
        }
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(Array(store.sketch.tracks.enumerated()), id: \.element.id) { index, track in
                    StickyClefView(
                        track: track,
                        layout: layout,
                        rowHeight: rowHeight,
                        leadingBarNumber: index == 0 ? layout.bar(atContentX: horizontalOffset + layout.stickyWidth + 1) : nil
                    )
                    .overlay(alignment: .bottom) { Palette.ruleSoft.frame(height: 1) }
                }
            }
            .allowsHitTesting(false)
        }
    }
}
