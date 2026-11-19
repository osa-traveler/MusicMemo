import Foundation
import MusicMemoCore

let usage = """
使い方：midi2musicmemo [オプション] 入力.mid ...

MIDI ファイル（.mid）を MusicMemo の曲（.musicmemo）に変換する。
出力は入力と同じフォルダに「元の名前.musicmemo」で作る（曲名は元のファイル名）。

オプション：
  -o, --output パス     出力ファイル（入力が1つのとき）
  -d, --out-dir フォルダ  出力先のフォルダ
  --grid 16t|16         そろえる格子。16t = 16分と8分3連（初期値）、16 = 16分だけ
  --key "D major"       調を指定する（MIDI の調号より優先。例 "Bb major" "F# minor"）
  -f, --force           同じ名前の出力ファイルがあれば上書きする
  -h, --help            この説明
"""

struct Arguments {
    var inputs: [URL] = []
    var output: URL?
    var outDir: URL?
    var options = MIDIImportOptions()
    var force = false
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func parseKey(_ text: String) -> Key? {
    let parts = text.split(separator: " ")
    guard parts.count == 2, let tonic = Pitch.pitchClass(named: parts[0]) else { return nil }
    switch parts[1].lowercased() {
    case "major", "maj": return Key(tonic: tonic, mode: .major)
    case "minor", "min": return Key(tonic: tonic, mode: .minor)
    default: return nil
    }
}

func parseArguments() -> Arguments {
    var arguments = Arguments()
    var rest = CommandLine.arguments.dropFirst()
    func value(for flag: String) -> String {
        guard let value = rest.popFirst() else { fail("\(flag) の値がありません") }
        return value
    }
    while let argument = rest.popFirst() {
        switch argument {
        case "-h", "--help":
            print(usage)
            exit(0)
        case "-o", "--output": arguments.output = URL(fileURLWithPath: value(for: argument))
        case "-d", "--out-dir": arguments.outDir = URL(fileURLWithPath: value(for: argument), isDirectory: true)
        case "--grid":
            switch value(for: argument) {
            case "16t": arguments.options.grid = .sixteenthAndTriplet
            case "16": arguments.options.grid = .sixteenth
            default: fail("--grid は 16t か 16 です")
            }
        case "--key":
            let text = value(for: argument)
            guard let key = parseKey(text) else { fail("調が読めません：\(text)（例 \"D major\" \"F# minor\"）") }
            arguments.options.key = key
        case "-f", "--force": arguments.force = true
        default:
            if argument.hasPrefix("-") { fail("知らないオプションです：\(argument)\n\n\(usage)") }
            arguments.inputs.append(URL(fileURLWithPath: argument))
        }
    }
    if arguments.inputs.isEmpty { fail(usage) }
    if arguments.output != nil, arguments.inputs.count > 1 { fail("-o は入力が1つのときだけ使えます（複数なら -d）") }
    return arguments
}

let arguments = parseArguments()
var failures = 0
for input in arguments.inputs {
    let title = input.deletingPathExtension().lastPathComponent
    let output = arguments.output
        ?? (arguments.outDir ?? input.deletingLastPathComponent()).appendingPathComponent(title + ".musicmemo")
    print("■ \(input.lastPathComponent) → \(output.path)")
    do {
        if FileManager.default.fileExists(atPath: output.path), !arguments.force {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSLocalizedDescriptionKey: "出力ファイルがすでにあります（上書きするなら -f）"])
        }
        let result = try MIDIImporter.convert(Data(contentsOf: input), title: title, options: arguments.options)
        try result.file.encoded().write(to: output, options: .atomic)
        for line in result.report { print("  " + line) }
        for line in result.warnings { print("  ⚠︎ " + line) }
    } catch let error as SMFError {
        print("  ✗ \(error.description)")
        failures += 1
    } catch {
        print("  ✗ \(error.localizedDescription)")
        failures += 1
    }
}
exit(failures == 0 ? 0 : 1)
