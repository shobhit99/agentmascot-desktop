// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Morphling",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "MorphlingApp", targets: ["MorphlingApp"])],
    targets: [
        .executableTarget(name: "MorphlingApp", resources: [.process("Resources")]),
        .testTarget(name: "MorphlingTests", dependencies: ["MorphlingApp"])
    ]
)
