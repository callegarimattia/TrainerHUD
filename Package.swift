// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TrainerHUD",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TrainerHUD",
            path: "Sources/TrainerHUD"
        )
    ],
    swiftLanguageVersions: [.v5]
)
