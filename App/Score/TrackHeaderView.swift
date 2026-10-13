import MusicMemoCore
import SwiftUI

/// トラック情報（左列、幅196pt固定）。倍率に応じて4段階で表示を変える。
/// - 最小：楽器名＋役割だけ
/// - 縮小時：楽器名＋役割、音量スライダとパン値の1行
/// - 通常：楽器名＋役割、音量、パン
/// - 拡大時：通常＋ミュート／ソロ／音色選択
struct TrackHeaderView: View {
    enum Density {
        case minimal
        case compact
        case regular
        case detailed

        /// この表示が収まる行の高さ。
        var minimumRowHeight: CGFloat {
            switch self {
            case .minimal: 34
            case .compact: 58
            case .regular: 90
            case .detailed: 140
            }
        }
    }

    let track: Track
    let isSelected: Bool
    let density: Density
    var volume: Binding<Int>
    var pan: Binding<Int>
    var onToggleMute: () -> Void = {}
    var onToggleSolo: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: density == .detailed ? 8 : 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(track.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text(track.role.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .lineLimit(1)

            if density == .minimal {
                EmptyView()
            } else if density == .compact {
                parameterRow("Vol") {
                    CompactSlider(value: volume, range: Track.volumeRange)
                    panLabel
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    parameterRow("Vol") {
                        CompactSlider(value: volume, range: Track.volumeRange)
                    }
                    parameterRow("Pan") {
                        CompactSlider(value: pan, range: Track.panRange)
                        panLabel
                    }
                }
            }

            if density == .detailed {
                HStack(spacing: 8) {
                    toggleButton("M", isOn: track.isMuted, label: "ミュート", action: onToggleMute)
                    toggleButton("S", isOn: track.isSoloed, label: "ソロ", action: onToggleSolo)
                    // 音色の選択は未実装
                    headerButton { Text("音色…").font(.system(size: 13)) }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.leading, 14)  // 色バー4pt＋余白10pt
        .padding(.trailing, 12)
        .padding(.vertical, density == .minimal ? 4 : 8)
        .frame(width: Metrics.trackHeaderWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(isSelected ? Palette.accentTint : Palette.paper)
        .overlay(alignment: .leading) { track.color.color.frame(width: 4) }
        .overlay(alignment: .trailing) { Palette.rule.frame(width: 1) }
        .contentShape(Rectangle())
    }

    private var panLabel: some View {
        Text(track.panLabel)
            .frame(width: 26, alignment: .trailing)
            .monospacedDigit()
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

    private func toggleButton(_ title: String, isOn: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            headerButton(isOn: isOn) {
                Text(title).font(.system(size: 13, weight: .bold))
            }
            .frame(width: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func headerButton(isOn: Bool = false, @ViewBuilder label: () -> some View) -> some View {
        label()
            .foregroundStyle(isOn ? Palette.paper : Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(isOn ? Palette.ink : Palette.paper, in: .rect(cornerRadius: 8))
            .overlay {
                if !isOn { RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.ruleStrong, lineWidth: 1) }
            }
            .contentShape(.rect(cornerRadius: 8))
    }
}
