// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HomelabCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "HomelabCore", targets: ["HomelabCore"]),
    ],
    targets: [
        .target(
            name: "HomelabCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "HomelabCoreTests",
            dependencies: ["HomelabCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
