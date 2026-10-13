import MusicMemoCore
import SwiftUI

/// SPEC「ビジュアル仕様」の色。白い紙面に墨色、操作はコバルトブルー、コードはオレンジ、編集位置だけ赤。
enum Palette {
    static let background = Color(hex: 0xEEF0F2)
    static let paper = Color(hex: 0xFFFFFF)
    static let paperMuted = Color(hex: 0xF6F7F9)

    static let ink = Color(hex: 0x1B1D21)
    static let inkSecondary = Color(hex: 0x5A606B)
    static let inkTertiary = Color(hex: 0x8A909A)

    static let rule = Color(hex: 0xD9DCE1)
    static let ruleStrong = Color(hex: 0xC9CDD3)
    /// トラック行の区切り線。
    static let ruleSoft = Color(hex: 0xE4E6EA)

    static let accent = Color(hex: 0x2F5BEA)
    static let accentTint = Color(hex: 0xEAF0FE)
    static let accentTintStrong = Color(hex: 0xDCE5FD)

    static let chord = Color(hex: 0xC2541F)
    static let playhead = Color(hex: 0xD92D20)

    static let trackBlue = Color(hex: 0x2F5BEA)
    static let trackOrange = Color(hex: 0xC2541F)
    static let trackGreen = Color(hex: 0x3D7A5C)
    static let trackPurple = Color(hex: 0x7A5AB8)
    static let trackOchre = Color(hex: 0xB08A1E)
    static let trackGray = Color(hex: 0x5A606B)
}

extension TrackColor {
    var color: Color {
        switch self {
        case .blue: Palette.trackBlue
        case .orange: Palette.trackOrange
        case .green: Palette.trackGreen
        case .purple: Palette.trackPurple
        case .ochre: Palette.trackOchre
        case .gray: Palette.trackGray
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
