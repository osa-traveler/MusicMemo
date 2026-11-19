import MusicMemoCore
import SwiftUI

/// トラック情報（左列、幅196pt固定）。倍率に応じて4段階で表示を変える。
/// - 最小：楽器名＋役割だけ
/// - 縮小時：楽器名＋役割、音量スライダとパン値の1行
/// - 通常：楽器名＋役割、音量、パン
/// - 拡大時：通常＋音色選択
/// どの段階でも、楽器名の行の右端に M（ミュート）・S（ソロ）と「…」メニューを出す。
struct TrackHeaderView<MenuItems: View>: View {
    typealias Density = TrackHeaderDensity

    let track: Track
    let isSelected: Bool
    let density: Density
    /// ミュート・ソロで鳴っているか（鳴っていなければ楽器名を薄くする）。
    var isAudible = true
    var volume: Binding<Int>
    var pan: Binding<Int>
    var onToggleMute: () -> Void = {}
    var onToggleSolo: () -> Void = {}
    /// 「音色…」ボタン（トラックの設定を開く）。
    var onShowSettings: () -> Void = {}
    /// 右上の「…」メニュー（Mac は右クリックでも出す）の項目。
    @ViewBuilder var menuItems: () -> MenuItems

    var body: some View {
        VStack(alignment: .leading, spacing: density == .detailed ? 8 : 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Group {
                    Text(track.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .layoutPriority(1)
                    Text(track.role.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.inkSecondary)
                }
                .opacity(isAudible ? 1 : Palette.silentOpacity)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    smallToggle("M", isOn: track.isMuted, onColor: Palette.mute, onText: Palette.paper,
                                label: "ミュート", action: onToggleMute)
                    smallToggle("S", isOn: track.isSoloed, onColor: Palette.solo, onText: Palette.ink,
                                label: "ソロ", action: onToggleSolo)
                }
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
            .lineLimit(1)
            .padding(.trailing, 18)  // 「…」メニューの分
            .overlay(alignment: .topTrailing) { menuButton }

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
                    Button(action: onShowSettings) {
                        headerButton { Text("音色…").font(.system(size: 13)) }
                    }
                    .buttonStyle(.plain)
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

    private var menuButton: some View {
        Menu(content: menuItems) {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.inkTertiary)
                .frame(width: 24, height: 20)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .offset(x: 6, y: -1)
        .accessibilityLabel("\(track.name)のメニュー")
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

    /// 楽器名の行の M・S ボタン。押しているときは onColor で塗る。
    private func smallToggle(_ title: String, isOn: Bool, onColor: Color, onText: Color, label: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isOn ? onText : Palette.inkSecondary)
                .frame(width: 20, height: 18)
                .background(isOn ? onColor : Palette.paper, in: .rect(cornerRadius: 4))
                .overlay {
                    if !isOn { RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.ruleStrong, lineWidth: 1) }
                }
                .contentShape(.rect(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "オン" : "オフ")
    }

    private func headerButton(@ViewBuilder label: () -> some View) -> some View {
        label()
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(Palette.paper, in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.ruleStrong, lineWidth: 1) }
            .contentShape(.rect(cornerRadius: 8))
    }
}

/// トラック情報の表示の段階（倍率で決める）。
enum TrackHeaderDensity {
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
