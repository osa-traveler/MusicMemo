import MusicMemoCore
import SwiftUI

/// トラック情報（左列、幅196pt固定）。楽器名＋役割、音量、パン。
struct TrackHeaderView: View {
    let track: Track
    let isSelected: Bool
    var volume: Binding<Int>
    var pan: Binding<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(track.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text(track.role.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .lineLimit(1)
            parameterRow("Vol") {
                CompactSlider(value: volume, range: Track.volumeRange)
            }
            parameterRow("Pan") {
                CompactSlider(value: pan, range: Track.panRange)
                Text(track.panLabel)
                    .frame(width: 26, alignment: .trailing)
                    .monospacedDigit()
            }
        }
        .padding(.leading, 14)  // 色バー4pt＋余白10pt
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .frame(width: Metrics.trackHeaderWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(isSelected ? Palette.accentTint : Palette.paper)
        .overlay(alignment: .leading) { track.color.color.frame(width: 4) }
        .overlay(alignment: .trailing) { Palette.rule.frame(width: 1) }
        .contentShape(Rectangle())
    }

    private func parameterRow(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .frame(width: 24, alignment: .leading)
            content()
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.inkSecondary)
    }
}
