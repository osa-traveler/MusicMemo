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

/// メニュー：再生（再生／停止・ループ・メトロノーム）、編集（元に戻す／やり直す／切り取り／コピー／貼り付け／戻って消す／選んだ音の移動）、表示（拡大／縮小／100%に戻す）。
struct SketchCommands: Commands {
    @FocusedValue(\.sketchStore) private var store

    var body: some Commands {
        CommandMenu("再生") {
            Button(store?.isPlaying == true ? "停止" : "再生") { store?.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(store == nil || store?.isEditingText == true)
            Button("ループ") { store?.toggleLoop() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(store == nil)
            Button("メトロノーム") { store?.toggleMetronome() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(store == nil)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("元に戻す") { store?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(store?.canUndo != true || store?.isEditingText == true)
            Button("やり直す") { store?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(store?.canRedo != true || store?.isEditingText == true)
            Divider()
            Button(store?.hasNoteSelection == true ? "選んだ音を消す" : "戻って消す") { store?.deleteKey() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(store == nil || store?.isEditingText == true)
            Divider()
            // 選んだ音符の移動（←→ 16分、↑↓ 半音、⇧↑↓ オクターブ）
            Group {
                Button("選んだ音を左へ") { store?.nudgeSelection(ticks: -RulerView.seekGrid) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("選んだ音を右へ") { store?.nudgeSelection(ticks: RulerView.seekGrid) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("選んだ音を半音上げる") { store?.nudgeSelection(semitones: 1) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button("選んだ音を半音下げる") { store?.nudgeSelection(semitones: -1) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                Button("選んだ音を1オクターブ上げる") { store?.nudgeSelection(semitones: 12) }
                    .keyboardShortcut(.upArrow, modifiers: .shift)
                Button("選んだ音を1オクターブ下げる") { store?.nudgeSelection(semitones: -12) }
                    .keyboardShortcut(.downArrow, modifiers: .shift)
                Button("選択を解除") { store?.clearNoteSelection() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .disabled(store?.hasNoteSelection != true || store?.isPlaying == true || store?.isEditingText == true)
        }
        // 切り取り・コピー・貼り付け：名前などの文字を入力中は、文字の切り取り・コピー・貼り付けにする
        CommandGroup(replacing: .pasteboard) {
            Button("切り取り") { store?.isEditingText == false ? store?.cutSelection() : TextEditing.send(.cut) }
                .keyboardShortcut("x", modifiers: .command)
                .disabled(store?.isEditingText == false && (store?.hasNoteSelection != true || store?.isPlaying == true))
            Button("コピー") { store?.isEditingText == false ? store?.copySelection() : TextEditing.send(.copy) }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(store?.isEditingText == false && store?.hasNoteSelection != true)
            Button("貼り付け") { store?.isEditingText == false ? store?.paste() : TextEditing.send(.paste) }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(store?.isEditingText == false && store?.canPaste != true)
        }
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

/// 文字の入力欄への切り取り・コピー・貼り付け（メニューの項目を音符用にしたので、入力中は標準の動作へ送る）。
@MainActor
enum TextEditing {
    enum Action { case cut, copy, paste }

    static func send(_ action: Action) {
        #if os(macOS)
        let selector = switch action {
        case .cut: #selector(NSText.cut(_:))
        case .copy: #selector(NSText.copy(_:))
        case .paste: #selector(NSText.paste(_:))
        }
        NSApp.sendAction(selector, to: nil, from: nil)
        #else
        let selector = switch action {
        case .cut: #selector(UIResponderStandardEditActions.cut(_:))
        case .copy: #selector(UIResponderStandardEditActions.copy(_:))
        case .paste: #selector(UIResponderStandardEditActions.paste(_:))
        }
        UIApplication.shared.sendAction(selector, to: nil, from: nil, for: nil)
        #endif
    }
}
