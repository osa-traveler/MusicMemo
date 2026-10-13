import SwiftUI

/// トラック情報列の細いスライダ。iPad と Mac で同じ見た目にするため自前で描く。
struct CompactSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    private let trackHeight: CGFloat = 5
    private let thumbSize: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let usable = geometry.size.width - thumbSize
            let fraction = CGFloat(value - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
            let thumbX = usable * fraction
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.paper)
                    .overlay(Capsule().strokeBorder(Palette.ruleStrong, lineWidth: 1))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: thumbX + thumbSize / 2, height: trackHeight)
                Circle()
                    .fill(Palette.accent)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: thumbX)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = min(max((drag.location.x - thumbSize / 2) / usable, 0), 1)
                        let span = CGFloat(range.upperBound - range.lowerBound)
                        value = range.lowerBound + Int((fraction * span).rounded())
                    }
            )
        }
        .frame(height: 20)
    }
}
