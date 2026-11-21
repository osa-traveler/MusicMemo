/// 入力方法。鍵盤と譜面の直接タップ（MIDI キーボードはまだ無い）。
/// 譜面の直接タップを選んでいる間も、鍵盤と休符のボタンで入力できる。
enum InputMethod: CaseIterable {
    case keyboard
    case scoreTap
    case midiKeyboard

    var title: String {
        switch self {
        case .keyboard: "鍵盤"
        case .scoreTap: "譜面を直接タップ"
        case .midiKeyboard: "MIDIキーボード"
        }
    }

    var isAvailable: Bool { self != .midiKeyboard }
}
