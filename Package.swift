// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HearthstoneBGHelper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "HearthstoneBGHelper", targets: ["HearthstoneBGHelper"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "HearthstoneBGHelper",
            dependencies: [],
            path: "Sources/HearthstoneBGHelper",
            resources: [
                .process("Resources/BattlegroundsCards.json"),
                .process("Resources/TribeData.json")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
