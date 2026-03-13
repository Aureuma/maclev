// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "macLev",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "macLev", targets: ["macLev"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "macLev",
            path: "Sources/macLev"
        )
    ]
)
