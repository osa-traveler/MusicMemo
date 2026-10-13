import SwiftUI

/// 譜面ビュー右端の縦スクロールバー（幅8pt）。つまみの長さ＝表示中の高さ／全体の高さ（＝表示トラック数／全トラック数）。
/// つまみをドラッグしてもスクロールできる。
struct VerticalScrollbar: View {
    /// スクロール量・全体の高さ・表示中の高さ。
    let offset: CGFloat
    let contentHeight: CGFloat
    let visibleHeight: CGFloat
    let onScroll: (CGFloat) -> Void

    @State private var dragStartOffset: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let trackHeight = geometry.size.height
            let ratio = contentHeight > 0 ? min(visibleHeight / contentHeight, 1) : 1
            let thumbHeight = max(trackHeight * ratio, 24)
            let scrollable = max(contentHeight - visibleHeight, 0)
            let travel = trackHeight - thumbHeight
            let thumbY = scrollable > 0 ? travel * min(max(offset / scrollable, 0), 1) : 0

            ZStack(alignment: .top) {
                Capsule().fill(Palette.background)
                Capsule()
                    .fill(Palette.inkTertiary)
                    .frame(height: thumbHeight)
                    .offset(y: thumbY)
                    .gesture(
                        DragGesture()
                            .onChanged { drag in
                                guard scrollable > 0, travel > 0 else { return }
                                let start = dragStartOffset ?? offset
                                dragStartOffset = start
                                let target = start + drag.translation.height * scrollable / travel
                                onScroll(min(max(target, 0), scrollable))
                            }
                            .onEnded { _ in dragStartOffset = nil }
                    )
            }
        }
        .frame(width: 8)
    }
}
