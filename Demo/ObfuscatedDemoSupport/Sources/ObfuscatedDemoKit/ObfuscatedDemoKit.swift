/// ObfuscatedDemoKit — demo app API with a macro plugin that registers custom obfuscation steps.
///
/// Same surface as the ``Obfuscated`` product, but `#Obfuscated` uses ``ObfuscatedDemoMacros`` so
/// ``ObfuscationMethod/custom(id:parameters:)`` works for steps such as ``DemoRot13Step``.
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

/// Obfuscates a string literal at compile time (demo plugin — supports custom steps).
@freestanding(expression)
public macro Obfuscated(
    _ string: String,
    methods: [ObfuscationMethod]
) -> String = #externalMacro(module: "ObfuscatedDemoMacros", type: "ObfuscatedMacro")
