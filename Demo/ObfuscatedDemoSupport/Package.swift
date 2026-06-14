// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "ObfuscatedDemoSupport",
    platforms: [.macOS(.v15), .iOS(.v14), .tvOS(.v14), .watchOS(.v7), .macCatalyst(.v14)],
    products: [
        .library(
            name: "ObfuscatedDemoKit",
            targets: ["ObfuscatedDemoKit"]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", .upToNextMajor(from: "603.0.2")),
    ],
    targets: [
        .target(
            name: "ObfuscatedDemoSteps",
            dependencies: [
                .product(name: "ObfuscatedCore", package: "Obfuscated"),
            ]
        ),
        .macro(
            name: "ObfuscatedDemoMacros",
            dependencies: [
                "ObfuscatedDemoSteps",
                .product(name: "ObfuscatedMacroSupport", package: "Obfuscated"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "ObfuscatedDemoKit",
            dependencies: [
                .product(name: "ObfuscatedCore", package: "Obfuscated"),
                "ObfuscatedDemoSteps",
                "ObfuscatedDemoMacros",
            ]
        ),
    ]
)
