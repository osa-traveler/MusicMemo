/// GM（General MIDI）の音色表。プログラム番号は0始まり。名前は短い英語（トラック名にも使う）。
public enum GMInstruments {
    public struct Family: Identifiable, Sendable {
        /// 系統の名前（日本語）。
        public let name: String
        /// この系統のプログラム番号（8つ）。
        public let programs: Range<Int>
        public var id: Int { programs.lowerBound }
    }

    public static let families: [Family] = [
        "ピアノ", "クロマチック・パーカッション", "オルガン", "ギター",
        "ベース", "ストリングス", "アンサンブル", "ブラス",
        "リード", "パイプ", "シンセリード", "シンセパッド",
        "シンセエフェクト", "民族楽器", "打楽器", "効果音",
    ].enumerated().map { index, name in Family(name: name, programs: (index * 8)..<(index * 8 + 8)) }

    public static let names: [String] = [
        // ピアノ
        "Piano", "Bright Piano", "Electric Grand", "Honky-tonk", "E.Piano", "E.Piano 2", "Harpsichord", "Clavinet",
        // クロマチック・パーカッション
        "Celesta", "Glockenspiel", "Music Box", "Vibraphone", "Marimba", "Xylophone", "Tubular Bells", "Dulcimer",
        // オルガン
        "Drawbar Organ", "Perc Organ", "Rock Organ", "Church Organ", "Reed Organ", "Accordion", "Harmonica", "Bandoneon",
        // ギター
        "Nylon Guitar", "Steel Guitar", "Jazz Guitar", "Clean Guitar", "Muted Guitar", "Overdrive Guitar", "Distortion Guitar", "Guitar Harmonics",
        // ベース
        "Acoustic Bass", "Finger Bass", "Pick Bass", "Fretless Bass", "Slap Bass", "Slap Bass 2", "Synth Bass", "Synth Bass 2",
        // ストリングス
        "Violin", "Viola", "Cello", "Contrabass", "Tremolo Strings", "Pizzicato", "Harp", "Timpani",
        // アンサンブル
        "Strings", "Slow Strings", "Synth Strings", "Synth Strings 2", "Choir Aahs", "Voice Oohs", "Synth Voice", "Orchestra Hit",
        // ブラス
        "Trumpet", "Trombone", "Tuba", "Muted Trumpet", "French Horn", "Brass", "Synth Brass", "Synth Brass 2",
        // リード
        "Soprano Sax", "Alto Sax", "Tenor Sax", "Baritone Sax", "Oboe", "English Horn", "Bassoon", "Clarinet",
        // パイプ
        "Piccolo", "Flute", "Recorder", "Pan Flute", "Blown Bottle", "Shakuhachi", "Whistle", "Ocarina",
        // シンセリード
        "Square Lead", "Saw Lead", "Calliope Lead", "Chiff Lead", "Charang", "Voice Lead", "Fifths Lead", "Bass + Lead",
        // シンセパッド
        "New Age Pad", "Warm Pad", "Polysynth", "Choir Pad", "Bowed Pad", "Metallic Pad", "Halo Pad", "Sweep Pad",
        // シンセエフェクト
        "Rain", "Soundtrack", "Crystal", "Atmosphere", "Brightness", "Goblins", "Echoes", "Sci-Fi",
        // 民族楽器
        "Sitar", "Banjo", "Shamisen", "Koto", "Kalimba", "Bagpipe", "Fiddle", "Shanai",
        // 打楽器
        "Tinkle Bell", "Agogo", "Steel Drums", "Woodblock", "Taiko", "Melodic Tom", "Synth Drum", "Reverse Cymbal",
        // 効果音
        "Fret Noise", "Breath Noise", "Seashore", "Bird Tweet", "Telephone", "Helicopter", "Applause", "Gunshot",
    ]

    /// プログラム番号の名前（範囲外なら「Program 番号」）。
    public static func name(of program: Int) -> String {
        names.indices.contains(program) ? names[program] : "Program \(program)"
    }

    public static func family(of program: Int) -> Family? {
        families.first { $0.programs.contains(program) }
    }
}
