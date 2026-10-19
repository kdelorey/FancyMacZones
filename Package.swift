// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FancyMacZones",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FancyMacZones", targets: ["FancyMacZones"]),
        .library(name: "ZonesCore", targets: ["ZonesCore"]),
    ],
    targets: [
        .target(name: "ZonesCore"),
        .executableTarget(
            name: "FancyMacZones",
            dependencies: ["ZonesCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "ZonesCoreTests", dependencies: ["ZonesCore"]),
    ]
)
