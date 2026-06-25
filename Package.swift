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
    targets: [
        .executableTarget(
            name: "AirCopy"
        ),
        .testTarget(
            name: "AirCopyTests",
            dependencies: ["AirCopy"]
        )
    ]
)
