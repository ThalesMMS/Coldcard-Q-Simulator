// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ColdcardQSimulator",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ColdcardCore", targets: ["ColdcardCore"])
    ],
    targets: [
        .target(name: "BigInt", path: "Sources/BigInt"),
        .target(name: "ColdcardCore", dependencies: ["BigInt"], path: "Sources/ColdcardCore"),
        .testTarget(name: "ColdcardCoreTests", dependencies: ["ColdcardCore"], path: "Tests/ColdcardCoreTests")
    ]
)
