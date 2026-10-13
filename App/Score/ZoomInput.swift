import SwiftUI

#if os(macOS)
import AppKit

/// Mac の ⌘＋ホイールでのズーム。譜面ビューの上にマウスがあるときだけ反応する。
struct CommandScrollZoom: ViewModifier {
    /// 倍率の変化率と、マウスの位置（このビューの座標）を受け取る。
    let onZoom: (_ factor: Double, _ location: CGPoint) -> Void

    @State private var state = MonitorState()

    final class MonitorState {
        var hoverLocation: CGPoint?
        var monitor: Any?
    }

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): state.hoverLocation = location
                case .ended: state.hoverLocation = nil
                }
            }
            .onAppear {
                let state = state
                let onZoom = onZoom
                state.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    guard event.modifierFlags.contains(.command), let location = state.hoverLocation else { return event }
                    let sensitivity = event.hasPreciseScrollingDeltas ? 0.01 : 0.08
                    onZoom(exp(Double(event.scrollingDeltaY) * sensitivity), location)
                    return nil
                }
            }
            .onDisappear {
                if let monitor = state.monitor { NSEvent.removeMonitor(monitor) }
                state.monitor = nil
            }
    }
}
#endif

extension View {
    /// Mac では ⌘＋ホイールでズームする。iPad では何もしない。
    @ViewBuilder
    func commandScrollZoom(_ onZoom: @escaping (_ factor: Double, _ location: CGPoint) -> Void) -> some View {
        #if os(macOS)
        modifier(CommandScrollZoom(onZoom: onZoom))
        #else
        self
        #endif
    }
}

extension FocusedValues {
    /// メニューのコマンド（拡大／縮小）から操作する、いま前面にある曲。
    @Entry var sketchStore: SketchStore?
}

/// 表示メニュー：拡大／縮小／100%に戻す。
struct ZoomCommands: Commands {
    @FocusedValue(\.sketchStore) private var store

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("拡大") { store?.stepZoom(1) }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(store == nil)
            Button("縮小") { store?.stepZoom(-1) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(store == nil)
            Button("100%に戻す") { store?.setZoom(1) }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(store == nil)
        }
    }
}
