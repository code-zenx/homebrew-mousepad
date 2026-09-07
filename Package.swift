// swift-tools-version: 5.9
// ponytail: Swift 5 language mode on purpose. Strict concurrency + AppKit = friction. Tighten later.
import PackageDescription

let package = Package(
    name: "Mousepad",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MousepadCore", path: "Sources/MousepadCore"),
        .executableTarget(name: "Mousepad", dependencies: ["MousepadCore"], path: "Sources/Mousepad"),
        // `swift run MousepadCheck` — assert-based checks; the command line tools ship no XCTest.
        .executableTarget(name: "MousepadCheck", dependencies: ["MousepadCore"], path: "Tests/MousepadCheck"),
    ]
)
