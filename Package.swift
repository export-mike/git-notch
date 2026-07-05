// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "S8Notch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "S8Notch",
            path: "Sources/S8Notch"
        )
    ]
)
