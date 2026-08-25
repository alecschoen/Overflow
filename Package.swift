// swift-tools-version: 6.0
// Overflow — a Windows-style overflow popout for macOS menu bar icons.
import PackageDescription

let package = Package(
    name: "Overflow",
    platforms: [
        .macOS("14.2")
    ],
    products: [
        .executable(name: "OverflowApp", targets: ["OverflowApp"])
    ],
    targets: [
        .executableTarget(
            name: "OverflowApp",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
