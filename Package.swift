// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GitNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GitNotch",
            path: "Sources/GitNotch"
        )
    ]
)
