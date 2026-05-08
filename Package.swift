// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "hangCat",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "hangCat",
            path: "Sources/hangCat",
            resources: [.process("Resources")]
        )
    ]
)
