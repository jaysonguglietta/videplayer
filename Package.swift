// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VideoPlayer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "VideoPlayer", targets: ["VideoPlayer"])
    ],
    targets: [
        .executableTarget(
            name: "VideoPlayer",
            path: "Sources/VideoPlayer",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "VideoPlayerTests",
            dependencies: ["VideoPlayer"],
            path: "Tests/VideoPlayerTests"
        ),
        .testTarget(
            name: "VideoPlayerUITests",
            dependencies: ["VideoPlayer"],
            path: "Tests/VideoPlayerUITests"
        )
    ]
)
