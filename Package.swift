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
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", .upToNextMajor(from: "603.0.2")),
    ],
    targets: [
        .target(
            name: "ObfuscatedCore",
            dependencies: []
        ),
        .macro(
            name: "ObfuscatedMacros",
            dependencies: [
                "ObfuscatedCore",
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Obfuscated",
            dependencies: ["ObfuscatedCore", "ObfuscatedMacros"]
        ),
        .testTarget(
            name: "ObfuscatedCoreTests",
            dependencies: ["ObfuscatedCore"]
        ),
        .testTarget(
            name: "ObfuscatedTests",
            dependencies: [
                "ObfuscatedCore",
                "ObfuscatedMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
