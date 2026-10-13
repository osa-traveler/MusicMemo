#if DEBUG && os(macOS)
import AppKit

/// 開発用：環境変数 MUSICMEMO_SNAPSHOT にパスを渡して起動すると、
/// 基準サイズ（1194×834）のウィンドウを PNG に保存して終了する。
enum DebugSnapshot {
    @MainActor
    static func scheduleIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["MUSICMEMO_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // タイトルバーの下が 1194×834 になるようにする
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
            let titleBarHeight = window.frame.height - window.contentLayoutRect.height
            window.setContentSize(NSSize(width: 1194, height: 834 + titleBarHeight))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard let window = NSApp.windows.first(where: { $0.isVisible }),
                  let view = window.contentView
            else { exit(1) }
            let rect = view.convert(window.contentLayoutRect, from: nil)
            guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { exit(1) }
            view.cacheDisplay(in: rect, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }
}
#endif
