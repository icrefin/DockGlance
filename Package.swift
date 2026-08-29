// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DockGlance",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DockGlanceCore", path: "Sources/DockGlanceCore"),
        .executableTarget(
            name: "DockGlance",
            dependencies: ["DockGlanceCore"],
            path: "Sources/DockGlance"
        ),
        .executableTarget(
            name: "DockGlanceTests",
            dependencies: ["DockGlanceCore"],
            path: "Tests/DockGlanceTests"
        ),
    ]
)
