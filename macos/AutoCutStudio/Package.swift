// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutoCutStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AutoCutStudio", targets: ["AutoCutStudio"])
    ],
    targets: [
        .executableTarget(
            name: "AutoCutStudio",
            path: "Sources/AutoCutStudio"
        ),
        .testTarget(
            name: "AutoCutStudioTests",
            dependencies: ["AutoCutStudio"],
            path: "Tests/AutoCutStudioTests"
        ),
    ]
)
