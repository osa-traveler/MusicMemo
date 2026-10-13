import SwiftUI

/// 倍率HUD（譜面ビュー上部中央の暗いピル）。「− 倍率 ＋ ｜ 100%に戻す」。
struct ZoomHUD: View {
    let zoom: Double
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            hudButton(systemImage: "minus", label: "縮小", action: onZoomOut)
            Text("\(Int((zoom * 100).rounded()))%")
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
                .frame(minWidth: 64)
            hudButton(systemImage: "plus", label: "拡大", action: onZoomIn)
            Rectangle()
                .fill(.white.opacity(0.25))
                .frame(width: 1, height: 22)
                .padding(.horizontal, 6)
            Button(action: onReset) {
                Text("100%に戻す")
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .background(Color(hex: 0x2B2E33).opacity(0.95), in: .capsule)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    private func hudButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
