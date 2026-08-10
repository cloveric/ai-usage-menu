// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AIUsageMenu",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AIUsageCore", targets: ["AIUsageCore"]),
        .executable(name: "AIUsageMenu", targets: ["AIUsageMenu"]),
        .executable(name: "UsageProbe", targets: ["UsageProbe"]),
        .executable(name: "CoreChecks", targets: ["CoreChecks"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/steipete/CodexBar",
            revision: "648a948b7ab4e7703b42be4bac1c62bfe2eb64d0"),
    ],
    targets: [
        .target(
            name: "AIUsageCore",
            dependencies: [
                .product(name: "CodexBarCore", package: "CodexBar"),
            ]),
        .executableTarget(
            name: "AIUsageMenu",
            dependencies: ["AIUsageCore"],
            exclude: ["Resources"]),
        .executableTarget(
            name: "UsageProbe",
            dependencies: ["AIUsageCore"]),
        .executableTarget(
            name: "CoreChecks",
            dependencies: ["AIUsageCore"]),
    ])
