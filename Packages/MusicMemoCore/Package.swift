// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MusicMemoCore",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "MusicMemoCore", targets: ["MusicMemoCore"]),
    ],
    targets: [
        .target(name: "MusicMemoCore"),
        .testTarget(name: "MusicMemoCoreTests", dependencies: ["MusicMemoCore"]),
    ]
)
