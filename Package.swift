// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Morph",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MorphCore", targets: ["MorphCore"]),
        .executable(name: "morph", targets: ["morph"]),
        .executable(name: "MorphMac", targets: ["MorphMac"]),
    ],
    dependencies: [
        // Draws SVGs: ImageIO can't read them. Pure Swift, no network, zlib license.
        .package(url: "https://github.com/swhitty/SwiftDraw", from: "0.29.0"),
    ],
    targets: [
        .target(name: "MorphCore", dependencies: [.product(name: "SwiftDraw", package: "SwiftDraw")]),
        .executableTarget(name: "morph", dependencies: ["MorphCore"]),
        .executableTarget(name: "MorphMac", dependencies: ["MorphCore"]),
    ],
    swiftLanguageModes: [.v5]
)
