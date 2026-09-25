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
    targets: [
        .target(name: "MorphCore"),
        .executableTarget(name: "morph", dependencies: ["MorphCore"]),
        .executableTarget(name: "MorphMac", dependencies: ["MorphCore"]),
    ],
    swiftLanguageModes: [.v5]
)
