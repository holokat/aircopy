// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AirCopy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AirCopy",
            targets: ["AirCopy"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "AirCopy",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .testTarget(
            name: "AirCopyTests",
            dependencies: ["AirCopy"]
        )
    ]
)
