// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacZones",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacZones", targets: ["MacZones"]),
        .library(name: "ZonesCore", targets: ["ZonesCore"]),
    ],
    targets: [
        .target(name: "ZonesCore"),
        .executableTarget(
            name: "MacZones",
            dependencies: ["ZonesCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "ZonesCoreTests", dependencies: ["ZonesCore"]),
    ]
)
