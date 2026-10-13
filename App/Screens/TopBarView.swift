import MusicMemoCore
import SwiftUI

/// トップバー（高さ64）。戻る、曲名と曲の情報、再生／ループ／メトロノーム、元に戻す／やり直す、Logicへ書き出し。
/// 戻るボタン以外は動く。
struct TopBarView: View {
    let sketch: Sketch
    let isPlaying: Bool
    let isMetronomeOn: Bool
    let canUndo: Bool
    let canRedo: Bool
    let onTogglePlayback: () -> Void
    let onToggleMetronome: () -> Void
    let onToggleLoop: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onExport: (ExportFormat) -> Void

    var body: some View {
        HStack(spacing: 10) {
            iconButton("chevron.left", label: "スケッチ一覧へ戻る", size: 20, weight: .semibold) {}

            VStack(alignment: .leading, spacing: 2) {
                Text(sketch.title)
                    .font(.system(size: 17, weight: .bold))
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                transportButton(isPlaying ? "stop.fill" : "play.fill", label: isPlaying ? "停止" : "再生",
                                style: .primary, action: onTogglePlayback)
                transportButton("repeat", label: sketch.isLooping ? "ループ（オン）" : "ループ（オフ）",
                                style: sketch.isLooping ? .active : .plain, action: onToggleLoop)
                transportButton("metronome", label: isMetronomeOn ? "メトロノーム（オン）" : "メトロノーム（オフ）",
                                style: isMetronomeOn ? .active : .plain, action: onToggleMetronome)
            }
            .padding(4)
            .background(Palette.background, in: .rect(cornerRadius: 12))

            iconButton("arrow.uturn.backward", label: "元に戻す", action: onUndo)
                .disabled(!canUndo)
                .opacity(canUndo ? 1 : 0.35)
            iconButton("arrow.uturn.forward", label: "やり直す", action: onRedo)
                .disabled(!canRedo)
                .opacity(canRedo ? 1 : 0.35)

            Menu {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Button(format.title) { onExport(format) }
                }
            } label: {
                Label("Logicへ書き出し", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Palette.paper, in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.ruleStrong, lineWidth: 1))
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .frame(height: Metrics.topBarHeight)
        .foregroundStyle(Palette.ink)
        .background(Palette.paper)
        .overlay(alignment: .bottom) { Palette.rule.frame(height: 1) }
    }

    /// 「C major · 4/4 · ♩=96 · 16小節 · 4トラック」
    private var summary: String {
        let time = sketch.timeSignature
        let tempo = sketch.tempo.rounded() == sketch.tempo ? String(Int(sketch.tempo)) : String(format: "%.1f", sketch.tempo)
        return "\(sketch.key.description) · \(time.beats)/\(time.beatUnit) · ♩=\(tempo) · \(sketch.barCount)小節 · \(sketch.tracks.count)トラック"
    }

    private enum TransportStyle { case primary, active, plain }

    private func transportButton(_ symbol: String, label: String, style: TransportStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 40)
                .foregroundStyle(style == .primary ? Palette.paper : style == .active ? Palette.accent : Palette.ink)
                .background(
                    style == .primary ? Palette.accent : style == .active ? Palette.accentTintStrong : .clear,
                    in: .rect(cornerRadius: 9)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func iconButton(_ symbol: String, label: String, size: CGFloat = 18, weight: Font.Weight = .medium, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: weight))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
