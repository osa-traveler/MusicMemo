import SwiftUI

/// 1曲の編集画面。上から「トップバー／セクション行／譜面ビュー／全体ビュー／入力パレット」の5段で、譜面ビューだけが高さ可変。
/// 譜面ビュー以外はまだ枠だけ。
struct SketchScreen: View {
    @State private var store = SketchStore()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            VStack(spacing: Metrics.scoreAreaSpacing) {
                sectionRow
                scoreView
                overview
            }
            .padding(.horizontal, Metrics.outerHorizontalPadding)
            .padding(.top, Metrics.scoreAreaTopPadding)
            .padding(.bottom, Metrics.scoreAreaBottomPadding)
            inputPalette
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .focusedSceneValue(\.sketchStore, store)
        #if DEBUG
        .onAppear { DebugInputDemo.runIfRequested(store) }
        #endif
    }

    private var topBar: some View {
        TopBarView(sketch: store.sketch, canUndo: store.canUndo, canRedo: store.canRedo,
                   onToggleLoop: store.toggleLoop, onUndo: store.undo, onRedo: store.redo,
                   onExport: { Exporter.export(store.sketch, format: $0) })
    }

    private var sectionRow: some View {
        SectionBarView(store: store)
    }

    private var scoreView: some View {
        ScoreView(store: store)
            .frame(maxHeight: .infinity)
            .background(Palette.paper)
            .clipShape(.rect(cornerRadius: Metrics.panelCornerRadius))
        .shadow(color: Color(hex: 0x14161A, opacity: 0.06), radius: 1, y: 1)
    }

    private var overview: some View {
        OverviewView(store: store)
            .frame(height: Metrics.overviewHeight, alignment: .bottom)
            .padding(.leading, Metrics.trackHeaderWidth)
            .padding(.trailing, Metrics.verticalScrollbarWidth)
    }

    private var inputPalette: some View {
        InputPaletteView(store: store)
    }

    private func placeholder(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Palette.inkTertiary)
    }
}

#Preview(traits: .fixedLayout(width: 1194, height: 834)) {
    SketchScreen()
}
