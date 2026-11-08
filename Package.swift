// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Rea",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ReaCore", targets: ["ReaCore"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "ReaCore", path: "Sources/ReaCore"),
        .testTarget(
            name: "ReaCoreTests",
            dependencies: ["ReaCore"],
            path: "Tests/ReaCoreTests"
        ),
    ]
)
