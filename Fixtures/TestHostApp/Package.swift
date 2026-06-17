// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TestHostApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TestHostApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
