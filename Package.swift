// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "maclev",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "maclev", targets: ["maclev"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "maclev",
            path: "Sources/maclev"
        )
    ]
)
