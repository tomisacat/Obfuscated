/// Obfuscated — compile-time value obfuscation via Swift macros.
///
/// Import this module and use ``Obfuscated(_:methods:)``
/// to embed obfuscated secrets that decode to ordinary values at runtime.
///
/// See `docs/DOCUMENTATION.md` for the full API and algorithm reference.
import Foundation

@_exported import ObfuscatedCore

/// Re-exported pipeline method descriptor from ``ObfuscatedCore``.
public typealias ObfuscationMethod = ObfuscatedCore.ObfuscationMethod
/// Re-exported symmetric key wrapper from ``ObfuscatedCore``.
public typealias ObfuscatedKey = ObfuscatedCore.ObfuscatedKey
/// Re-exported AEAD nonce wrapper from ``ObfuscatedCore``.
public typealias ObfuscatedNonce = ObfuscatedCore.ObfuscatedNonce
/// Re-exported salt wrapper from ``ObfuscatedCore``.
public typealias ObfuscatedSalt = ObfuscatedCore.ObfuscatedSalt
/// Re-exported HKDF info wrapper from ``ObfuscatedCore``.
public typealias ObfuscatedInfo = ObfuscatedCore.ObfuscatedInfo
/// Re-exported custom step parameters from ``ObfuscatedCore``.
public typealias ObfuscationParameters = ObfuscatedCore.ObfuscationParameters
/// Re-exported custom step protocol from ``ObfuscatedCore``.
public typealias ObfuscationStep = ObfuscatedCore.ObfuscationStep
/// Re-exported custom step registry from ``ObfuscatedCore``.
public typealias ObfuscationStepRegistry = ObfuscatedCore.ObfuscationStepRegistry
/// Re-exported supported obfuscated value protocol from ``ObfuscatedCore``.
public typealias ObfuscatedValue = ObfuscatedCore.ObfuscatedValue

/// Obfuscates a string literal at compile time and returns a normal `String` at runtime.
@freestanding(expression)
public macro Obfuscated(
    _ string: String,
    methods: [ObfuscationMethod]
) -> String = #externalMacro(module: "ObfuscatedMacros", type: "ObfuscatedMacro")

/// Obfuscates an integer literal at compile time and returns a normal `Int` at runtime.
@freestanding(expression)
public macro Obfuscated(
    _ value: Int,
    methods: [ObfuscationMethod]
) -> Int = #externalMacro(module: "ObfuscatedMacros", type: "ObfuscatedMacro")

/// Obfuscates a boolean literal at compile time and returns a normal `Bool` at runtime.
@freestanding(expression)
public macro Obfuscated(
    _ value: Bool,
    methods: [ObfuscationMethod]
) -> Bool = #externalMacro(module: "ObfuscatedMacros", type: "ObfuscatedMacro")

/// Obfuscates a byte array literal at compile time and returns ``Data`` at runtime.
@freestanding(expression)
public macro Obfuscated(
    _ bytes: [UInt8],
    methods: [ObfuscationMethod]
) -> Data = #externalMacro(module: "ObfuscatedMacros", type: "ObfuscatedMacro")

/// Obfuscates a ``CaseIterable`` enum case at compile time and returns the case at runtime.
///
/// Use `Type.case` syntax (e.g. `Environment.production`). The case name is obfuscated as a string.
/// Works for any ``CaseIterable`` enum, including those that also conform to ``RawRepresentable`` —
/// use the `as: Type.self` overload instead when you want to hide the raw value.
@freestanding(expression)
public macro Obfuscated<Enum: CaseIterable & Sendable>(
    _ enumCase: Enum,
    methods: [ObfuscationMethod]
) -> Enum = #externalMacro(module: "ObfuscatedMacros", type: "ObfuscatedMacro")

/// Obfuscates a ``RawRepresentable`` integer raw value at compile time.
@freestanding(expression)
public macro Obfuscated<Enum: RawRepresentable>(
    _ rawValue: Int,
    as type: Enum.Type,
    methods: [ObfuscationMethod]
) -> Enum = #externalMacro(module: "ObfuscatedMacros", type: "ObfuscatedMacro")

/// Obfuscates a ``RawRepresentable`` string raw value at compile time.
@freestanding(expression)
public macro Obfuscated<Enum: RawRepresentable>(
    _ rawValue: String,
    as type: Enum.Type,
    methods: [ObfuscationMethod]
) -> Enum = #externalMacro(module: "ObfuscatedMacros", type: "ObfuscatedMacro")
