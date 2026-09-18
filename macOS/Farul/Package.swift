// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Farul",
    defaultLocalization: "ro",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Farul",
            path: "Sources/Farul"
        )
    ]
)
