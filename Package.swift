// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fold",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Fold", targets: ["Fold"]), .library(name: "FoldCore", targets: ["FoldCore"])],
    targets: [
        .target(name: "FoldCore"),
        .executableTarget(name: "Fold", dependencies: ["FoldCore"]),
        .testTarget(name: "FoldCoreTests", dependencies: ["FoldCore"])
    ],
    swiftLanguageModes: [.v5]
)
