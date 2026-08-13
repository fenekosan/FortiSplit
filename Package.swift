// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FortiSplit",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FortiSplit",
            path: "Sources/FortiSplit"
        )
    ]
)
