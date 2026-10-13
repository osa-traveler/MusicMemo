/// 入力方法。いまは鍵盤だけ（譜面の直接タップと MIDI キーボードは詳細が未決）。
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

    var isAvailable: Bool { self == .keyboard }
}
