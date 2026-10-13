import CoreText
import SwiftUI

/// Bravura（SMuFL）のグリフ。コードポイントは SMuFL の規定どおり。
enum Glyph: UInt32, CaseIterable {
    case gClef = 0xE050
    case fClef = 0xE062
    case timeSig0 = 0xE080, timeSig1, timeSig2, timeSig3, timeSig4, timeSig5, timeSig6, timeSig7, timeSig8, timeSig9
    case noteheadWhole = 0xE0A2
    case noteheadHalf = 0xE0A3
    case noteheadBlack = 0xE0A4
    case augmentationDot = 0xE1E7
    case flag8thUp = 0xE240
    case flag8thDown = 0xE241
    case flag16thUp = 0xE242
    case flag16thDown = 0xE243
    case accidentalFlat = 0xE260
    case accidentalNatural = 0xE261
    case accidentalSharp = 0xE262
    case restWhole = 0xE4E3
    case restHalf = 0xE4E4
    case restQuarter = 0xE4E5
    case rest8th = 0xE4E6
    case rest16th = 0xE4E7

    static func timeSigDigit(_ digit: Int) -> Glyph {
        Glyph(rawValue: timeSig0.rawValue + UInt32(digit))!
    }
}

/// グリフの輪郭。単位は譜線間隔（1 = 五線の線と線の間）、原点はグリフの基準点、y は下向き。
enum SMuFL {
    private static let paths: [Glyph: Path] = {
        guard let url = Bundle.main.url(forResource: "Bravura", withExtension: "otf"),
              let data = try? Data(contentsOf: url) as CFData,
              let descriptor = CTFontManagerCreateFontDescriptorFromData(data)
        else {
            assertionFailure("Bravura.otf を読み込めない")
            return [:]
        }
        // SMuFL は 1em = 4譜線間隔。サイズ4で作ると 1pt = 1譜線間隔になる。
        let font = CTFontCreateWithFontDescriptor(descriptor, 4, nil)
        var flip = CGAffineTransform(scaleX: 1, y: -1)
        var result: [Glyph: Path] = [:]
        for glyph in Glyph.allCases {
            var characters = Array(String(UnicodeScalar(glyph.rawValue)!).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count),
                  let path = CTFontCreatePathForGlyph(font, glyphs[0], &flip)
            else { continue }
            result[glyph] = Path(path)
        }
        return result
    }()

    /// グリフを基準点 point に、譜線間隔 staffSpace の大きさで描く。
    static func draw(_ glyph: Glyph, at point: CGPoint, staffSpace: CGFloat, color: Color, in context: GraphicsContext) {
        guard let path = paths[glyph] else { return }
        let transform = CGAffineTransform(translationX: point.x, y: point.y).scaledBy(x: staffSpace, y: staffSpace)
        context.fill(path.applying(transform), with: .color(color))
    }
}
