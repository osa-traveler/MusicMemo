import SwiftUI

/// 1曲の編集画面。上から「トップバー／セクション行／譜面ビュー／全体ビュー／入力パレット」の5段で、譜面ビューだけが高さ可変。
/// Step 0 では各領域の枠だけを置く。
struct SketchScreen: View {
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
    }

    private var topBar: some View {
        placeholder("トップバー")
            .frame(height: Metrics.topBarHeight)
            .frame(maxWidth: .infinity)
            .background(Palette.paper)
            .overlay(alignment: .bottom) { Palette.rule.frame(height: 1) }
    }

    private var sectionRow: some View {
        placeholder("セクション行")
            .frame(height: Metrics.sectionRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scoreView: some View {
        HStack(spacing: 0) {
            placeholder("トラック情報")
                .frame(width: Metrics.trackHeaderWidth)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .trailing) { Palette.rule.frame(width: 1) }
            placeholder("譜面ビュー")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Color.clear
                .frame(width: Metrics.verticalScrollbarWidth)
        }
        .background(Palette.paper, in: .rect(cornerRadius: Metrics.panelCornerRadius))
        .shadow(color: Color(hex: 0x14161A, opacity: 0.06), radius: 1, y: 1)
    }

    private var overview: some View {
        placeholder("全体ビュー")
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.overviewHeight)
            .background(Palette.accentTint.opacity(0.5), in: .rect(cornerRadius: 8))
            .padding(.leading, Metrics.trackHeaderWidth)
            .padding(.trailing, Metrics.verticalScrollbarWidth)
    }

    private var inputPalette: some View {
        HStack(spacing: 18) {
            placeholder("音価")
                .frame(width: Metrics.durationBlockWidth)
                .frame(maxHeight: .infinity)
                .background(Palette.background.opacity(0.6), in: .rect(cornerRadius: Metrics.buttonCornerRadius))
            placeholder("鍵盤")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background.opacity(0.6), in: .rect(cornerRadius: Metrics.buttonCornerRadius))
            placeholder("入力方法")
                .frame(width: Metrics.inputMethodBlockWidth)
                .frame(maxHeight: .infinity)
                .background(Palette.background.opacity(0.6), in: .rect(cornerRadius: Metrics.buttonCornerRadius))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(height: Metrics.paletteHeight)
        .background(Palette.paper)
        .overlay(alignment: .top) { Palette.rule.frame(height: 1) }
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
