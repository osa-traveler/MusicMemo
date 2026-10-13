import Foundation

/// 画面状態（曲データとは別に持つ）。スクロール位置は Step 3 で足す。
public struct EditorState: Hashable, Codable, Sendable {
    /// 編集位置（赤い縦線）。音符はここに入力する。
    public var editPosition: Tick
    public var selectedTrackID: UUID?
    /// 譜面の倍率。1 = 100%。
    public var zoom: Double
    /// 入力パレットで選択中の音価。
    public var duration: NoteDuration
    /// 入力パレットのタイ。次に入力する音を前の音と繋ぐ。
    public var isTieOn: Bool
    /// 入力予定の音高（押している鍵など）。編集位置に半透明で表示する。
    public var previewPitch: MIDINote?

    public init(
        editPosition: Tick = 0,
        selectedTrackID: UUID? = nil,
        zoom: Double = 1,
        duration: NoteDuration = NoteDuration(.quarter),
        isTieOn: Bool = false,
        previewPitch: MIDINote? = nil
    ) {
        self.editPosition = editPosition
        self.selectedTrackID = selectedTrackID
        self.zoom = zoom
        self.duration = duration
        self.isTieOn = isTieOn
        self.previewPitch = previewPitch
    }
}
