// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PasteFlow",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PasteFlow", targets: ["PasteFlow"])
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "Sparkle",
            path: "Frameworks/Sparkle.xcframework"
        ),
        .executableTarget(
            name: "PasteFlow",
            dependencies: [
                "Sparkle"
            ],
            path: "Sources/PasteFlow",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
