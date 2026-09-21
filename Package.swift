// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MotionWall",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "motionwall",
            path: "Sources/motionwall",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
