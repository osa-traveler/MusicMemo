/// GM のドラム（10ch の音番号）を、ドラム譜の位置と符頭に対応させる。
/// 位置は五線上の位置（第1線 = 0、第5線 = 8。奇数は間）。一般的なドラム譜の並び：
/// バスドラム＝第1間、スネア＝第3間、タム＝第2〜4線あたり、ハイハット＝五線の上（×）、シンバル＝上第1線（×）。
/// 声部は、手で叩く楽器（符幹が上）と足で踏む楽器（バスドラム・ハイハットのペダル。符幹が下）の2つ。
public enum DrumMap {
    public struct Instrument: Sendable {
        public var name: String
        public var staffPosition: Int
        /// 符頭を × にする（シンバル類）。
        public var isCross: Bool
        /// 足で踏む楽器（2つ目の声部、符幹が下）。
        public var isFoot: Bool
    }

    static let instruments: [MIDINote: Instrument] = [
        35: Instrument(name: "Kick 2", staffPosition: 1, isCross: false, isFoot: true),
        36: Instrument(name: "Kick", staffPosition: 1, isCross: false, isFoot: true),
        37: Instrument(name: "Side Stick", staffPosition: 5, isCross: true, isFoot: false),
        38: Instrument(name: "Snare", staffPosition: 5, isCross: false, isFoot: false),
        39: Instrument(name: "Hand Clap", staffPosition: 5, isCross: true, isFoot: false),
        40: Instrument(name: "Snare 2", staffPosition: 5, isCross: false, isFoot: false),
        41: Instrument(name: "Low Floor Tom", staffPosition: 2, isCross: false, isFoot: false),
        42: Instrument(name: "Closed Hi-Hat", staffPosition: 9, isCross: true, isFoot: false),
        43: Instrument(name: "High Floor Tom", staffPosition: 3, isCross: false, isFoot: false),
        44: Instrument(name: "Pedal Hi-Hat", staffPosition: -1, isCross: true, isFoot: true),
        45: Instrument(name: "Low Tom", staffPosition: 4, isCross: false, isFoot: false),
        46: Instrument(name: "Open Hi-Hat", staffPosition: 9, isCross: true, isFoot: false),
        47: Instrument(name: "Low-Mid Tom", staffPosition: 6, isCross: false, isFoot: false),
        48: Instrument(name: "Hi-Mid Tom", staffPosition: 6, isCross: false, isFoot: false),
        49: Instrument(name: "Crash", staffPosition: 10, isCross: true, isFoot: false),
        50: Instrument(name: "High Tom", staffPosition: 7, isCross: false, isFoot: false),
        51: Instrument(name: "Ride", staffPosition: 8, isCross: true, isFoot: false),
        52: Instrument(name: "China", staffPosition: 10, isCross: true, isFoot: false),
        53: Instrument(name: "Ride Bell", staffPosition: 8, isCross: true, isFoot: false),
        55: Instrument(name: "Splash", staffPosition: 10, isCross: true, isFoot: false),
        57: Instrument(name: "Crash 2", staffPosition: 10, isCross: true, isFoot: false),
        59: Instrument(name: "Ride 2", staffPosition: 8, isCross: true, isFoot: false),
    ]

    /// 上の表に無い打楽器（タンバリン、カウベル、ラテン系など）は、シンバルの上（上第1間）に × で書く。
    static let otherInstrument = Instrument(name: "Percussion", staffPosition: 11, isCross: true, isFoot: false)

    public static func instrument(_ pitch: MIDINote) -> Instrument {
        instruments[pitch] ?? Instrument(name: "Percussion \(pitch)", staffPosition: otherInstrument.staffPosition,
                                         isCross: otherInstrument.isCross, isFoot: otherInstrument.isFoot)
    }

    public static func staffPosition(of pitch: MIDINote) -> Int { instrument(pitch).staffPosition }
    public static func isCross(_ pitch: MIDINote) -> Bool { instrument(pitch).isCross }
    public static func isFoot(_ pitch: MIDINote) -> Bool { instrument(pitch).isFoot }

    /// 五線上の位置にある代表の楽器（譜面上で音符を上下に動かすときに使う）。表に無い位置は一番近い位置の楽器。
    static let primary: [Int: MIDINote] = [-1: 44, 1: 36, 2: 41, 3: 43, 4: 45, 5: 38, 6: 48, 7: 50, 8: 51, 9: 42, 10: 49, 11: 56]

    public static func pitch(atStaffPosition position: Int) -> MIDINote {
        if let pitch = primary[position] { return pitch }
        let nearest = primary.keys.min { abs($0 - position) < abs($1 - position) } ?? 5
        return primary[nearest] ?? 38
    }
}
