// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mascot",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Mascot",
            resources: [
                .copy("haland_out.mov")
            ]
        )
    ]
)
