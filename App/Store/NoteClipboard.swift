import MusicMemoCore
import Observation

/// 音符のクリップボード（アプリの中だけ。開いているどの曲にも貼れる）。
/// コピーした音符をトラックごとに持つ。貼るときは、一番早い音符（origin）を編集位置に合わせる。
@MainActor
@Observable
final class NoteClipboard {
    static let shared = NoteClipboard()

    struct Part: Equatable {
        /// ドラムの音符か（ドラムはドラムのトラックにだけ、ほかはドラム以外のトラックにだけ貼る）。
        var isDrums: Bool
        /// コピー元のトラックの並び（ドラム以外のトラックで数えた順番）。トラックをまたいだコピーを貼るとき、間隔をそのまま保つ。
        var row: Int
        var notes: [Note]
    }

    struct Content: Equatable {
        var parts: [Part]
        /// 一番早い音符の位置。
        var origin: Tick
        /// 一番早い音符の頭から、一番遅い音符の終わりまで。
        var length: Tick
    }

    private(set) var content: Content?

    func set(_ content: Content) {
        self.content = content
    }
}
