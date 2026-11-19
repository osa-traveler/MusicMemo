// swift-tools-version: 6.0
import PackageDescription

// 変換の処理は MusicMemoCore（MIDIImporter）にあり、アプリの「MIDI を読み込む…」と共通。ここはコマンドの入口だけ。
let package = Package(
    name: "midi2musicmemo",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "midi2musicmemo", targets: ["midi2musicmemo"]),
    ],
    dependencies: [
        .package(path: "../../Packages/MusicMemoCore"),
    ],
    targets: [
        .executableTarget(name: "midi2musicmemo", dependencies: ["MusicMemoCore"]),
    ]
)
