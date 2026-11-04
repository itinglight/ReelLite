// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ReelLite",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ReelLite",
            path: "Sources/ReelLite"
        )
    ]
)
