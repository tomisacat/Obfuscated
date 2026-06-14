/// ObfuscatedDemoKit — demo app API with a macro plugin that registers custom obfuscation steps.
///
/// Same surface as the ``Obfuscated`` product, but `#Obfuscated` uses ``ObfuscatedDemoMacros`` so
/// ``ObfuscationMethod/custom(id:parameters:)`` works for steps such as ``DemoRot13Step``.
import Foundation

@_exported import ObfuscatedCore
@_exported import ObfuscatedDemoSteps

public typealias ObfuscationMethod = ObfuscatedCore.ObfuscationMethod
public typealias ObfuscatedKey = ObfuscatedCore.ObfuscatedKey
public typealias ObfuscatedNonce = ObfuscatedCore.ObfuscatedNonce
public typealias ObfuscatedSalt = ObfuscatedCore.ObfuscatedSalt
public typealias ObfuscatedInfo = ObfuscatedCore.ObfuscatedInfo
public typealias ObfuscationParameters = ObfuscatedCore.ObfuscationParameters
public typealias ObfuscationStep = ObfuscatedCore.ObfuscationStep
public typealias ObfuscationStepRegistry = ObfuscatedCore.ObfuscationStepRegistry
public typealias ObfuscatedValue = ObfuscatedCore.ObfuscatedValue

@freestanding(expression)
public macro Obfuscated(
    _ string: String,
    methods: [ObfuscationMethod]
) -> String = #externalMacro(module: "ObfuscatedDemoMacros", type: "ObfuscatedMacro")

@freestanding(expression)
public macro Obfuscated(
    _ value: Int,
    methods: [ObfuscationMethod]
) -> Int = #externalMacro(module: "ObfuscatedDemoMacros", type: "ObfuscatedMacro")

@freestanding(expression)
public macro Obfuscated(
    _ value: Bool,
    methods: [ObfuscationMethod]
) -> Bool = #externalMacro(module: "ObfuscatedDemoMacros", type: "ObfuscatedMacro")

@freestanding(expression)
public macro Obfuscated(
    _ bytes: [UInt8],
    methods: [ObfuscationMethod]
) -> Data = #externalMacro(module: "ObfuscatedDemoMacros", type: "ObfuscatedMacro")

@freestanding(expression)
public macro Obfuscated<Enum: CaseIterable & Sendable>(
    _ enumCase: Enum,
    methods: [ObfuscationMethod]
) -> Enum = #externalMacro(module: "ObfuscatedDemoMacros", type: "ObfuscatedMacro")

@freestanding(expression)
public macro Obfuscated<Enum: RawRepresentable>(
    _ rawValue: Int,
    as type: Enum.Type,
    methods: [ObfuscationMethod]
) -> Enum = #externalMacro(module: "ObfuscatedDemoMacros", type: "ObfuscatedMacro")

@freestanding(expression)
public macro Obfuscated<Enum: RawRepresentable>(
    _ rawValue: String,
    as type: Enum.Type,
    methods: [ObfuscationMethod]
) -> Enum = #externalMacro(module: "ObfuscatedDemoMacros", type: "ObfuscatedMacro")
