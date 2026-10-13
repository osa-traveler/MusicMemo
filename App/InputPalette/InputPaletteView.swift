import MusicMemoCore
import SwiftUI

/// 入力パレット（画面下部、高さ206）。左から 音価／音高（鍵盤）／入力方法。
struct InputPaletteView: View {
    let store: SketchStore

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            DurationPadView(store: store)
                .frame(width: Metrics.durationBlockWidth)
            PianoKeyboardBlock(store: store)
                .frame(maxWidth: .infinity)
            InputMethodView(store: store)
                .frame(width: Metrics.inputMethodBlockWidth)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(height: Metrics.paletteHeight)
        .frame(maxWidth: .infinity)
        .background(Palette.paper)
        .overlay(alignment: .top) { Palette.rule.frame(height: 1) }
    }
}

/// パレットの各ブロックの見出し。
struct PaletteHeading: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Palette.inkSecondary)
    }
}

/// 入力方法：鍵盤／譜面を直接タップ／MIDIキーボード。
struct InputMethodView: View {
    let store: SketchStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaletteHeading("入力方法")
            ForEach(InputMethod.allCases, id: \.self) { method in
                let isSelected = store.inputMethod == method
                Button {
                    store.inputMethod = method
                } label: {
                    Text(method.title)
                        .font(.system(size: 14, weight: isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? Palette.paper : Palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(isSelected ? Palette.ink : Palette.paper, in: .rect(cornerRadius: 10))
                        .overlay {
                            if !isSelected { RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.rule, lineWidth: 1) }
                        }
                        .contentShape(.rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(!method.isAvailable)
                .opacity(method.isAvailable ? 1 : 0.6)
            }
            Spacer(minLength: 0)
            Text("入力後は自動で次の拍へ進む")
                .font(.system(size: 11))
                .foregroundStyle(Palette.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
