#if os(iOS)
import SwiftUI
import UIKit

/// iPad：長押ししてからのドラッグ（範囲選択の箱）。
/// UIKit の長押しは、指が動く前に認識されるので、普通のドラッグ（譜面のスクロール）とぶつからない。
struct LongPressDragGesture: UIGestureRecognizerRepresentable {
    var minimumDuration: TimeInterval = 0.3
    /// 位置はこのジェスチャーを付けたビューの座標。
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    var onEnded: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumDuration
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let location = context.converter.localLocation
        switch recognizer.state {
        case .began: onBegan(location)
        case .changed: onChanged(location)
        case .ended, .cancelled, .failed: onEnded()
        default: break
        }
    }
}
#endif
