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
        .executableTarget(
            name: "PasteFlow",
            dependencies: [],
            path: "Sources/PasteFlow",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
