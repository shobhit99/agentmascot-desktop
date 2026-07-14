// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Morphling",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "MorphlingApp", targets: ["MorphlingApp"])],
    targets: [
        .executableTarget(
            name: "MorphlingApp",
            exclude: [
                "Resources/Mascots/haland.apng",
                "Resources/Mascots/haland_out.mov"
            ],
            resources: [
                .process("Resources/Hooks"),
                .process("Resources/Mascots/HalandFramesV2"),
                .process("Resources/Mascots/MascotIdle.svg"),
                .process("Resources/Mascots/MascotWorking.svg"),
                .process("Resources/Mascots/MascotNeedsInput.svg")
            ]
        ),
        .testTarget(name: "MorphlingTests", dependencies: ["MorphlingApp"])
    ]
)
