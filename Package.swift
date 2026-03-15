// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TempoApp",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(
            name: "TempoApp",
            targets: ["TempoApp"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "TempoApp",
            path: "Sources/TempoApp"
        ),
        .testTarget(
            name: "TempoAppTests",
            dependencies: ["TempoApp"],
            path: "Tests/TempoAppTests"
        ),
    ]
)
