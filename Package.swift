// swift-tools-version: 6.2

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Obfuscated",
    platforms: [.macOS(.v15), .iOS(.v14), .tvOS(.v14), .watchOS(.v7), .macCatalyst(.v14)],
    products: [
        .library(
            name: "Obfuscated",
            targets: ["Obfuscated"]
        ),
        .library(
            name: "ObfuscatedCore",
            targets: ["ObfuscatedCore"]
        ),
        .library(
            name: "ObfuscatedMacroSupport",
            targets: ["ObfuscatedMacroSupport"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", .upToNextMajor(from: "603.0.2")),
    ],
    targets: [
        .target(
            name: "ObfuscatedCore",
            dependencies: []
        ),
        .target(
            name: "ObfuscatedMacroSupport",
            dependencies: [
                "ObfuscatedCore",
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ]
        ),
        .macro(
            name: "ObfuscatedMacros",
            dependencies: [
                "ObfuscatedMacroSupport",
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Obfuscated",
            dependencies: ["ObfuscatedCore", "ObfuscatedMacros"]
        ),
        .testTarget(
            name: "ObfuscatedCoreTests",
            dependencies: ["ObfuscatedCore", "ObfuscatedTestSupport"]
        ),
        .testTarget(
            name: "ObfuscatedTests",
            dependencies: [
                "ObfuscatedCore",
                "ObfuscatedMacroSupport",
                "ObfuscatedTestSupport",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "ObfuscatedTestSupport",
            dependencies: ["ObfuscatedCore"],
            path: "Tests/ObfuscatedTestSupport"
        ),
    ]
)
