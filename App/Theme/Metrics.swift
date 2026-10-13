import CoreGraphics

/// 寸法（pt）。基準は iPad 11インチ横向き 1194×834。値は docs/reference/01_main_100.html から。
enum Metrics {
    // トップバー
    static let topBarHeight: CGFloat = 64

    // 譜面＋全体ビューの領域
    static let outerHorizontalPadding: CGFloat = 18
    static let scoreAreaTopPadding: CGFloat = 14
    static let scoreAreaBottomPadding: CGFloat = 12
    static let scoreAreaSpacing: CGFloat = 10

    // セクション行
    static let sectionRowHeight: CGFloat = 24

    // 譜面ビュー
    static let trackHeaderWidth: CGFloat = 196
    static let verticalScrollbarWidth: CGFloat = 16
    static let playRangeBarHeight: CGFloat = 18
    static let rulerHeight: CGFloat = 28

    // 全体ビュー
    static let overviewHeight: CGFloat = 70
    static let overviewCardHeight: CGFloat = 46

    // 入力パレット
    static let paletteHeight: CGFloat = 206
    static let durationBlockWidth: CGFloat = 228
    static let inputMethodBlockWidth: CGFloat = 168

    // 角丸
    static let panelCornerRadius: CGFloat = 14
    static let buttonCornerRadius: CGFloat = 10
}
