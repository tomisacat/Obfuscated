/// Obfuscated — compile-time string obfuscation via Swift macros.
///
/// Import this module and use ``Obfuscated(_:methods:)``
/// to embed obfuscated secrets that decode to ordinary `String` values at runtime.
///
/// See the package `DOCUMENTATION.md` for the full API and algorithm reference.
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

/// Obfuscates a string literal at compile time and returns a normal `String` at runtime.
///
/// The macro encodes the string using the given methods, embeds the obfuscated bytes and any
/// crypto material into the binary, and expands to a call to ``ObfuscatedRuntime/_decode(bytes:methods:material:)``.
///
/// ```swift
/// let apiKey = #Obfuscated("sk_live_xxx", methods: [.xor(key: 0x5A), .base64])
/// print(apiKey) // "sk_live_xxx"
///
/// let header = #Obfuscated("Bearer \("abc")", methods: [.xor(key: 0x5A)])
/// // folds to "Bearer abc" at compile time, then obfuscates the whole string
/// ```
///
/// - Parameters:
///   - string: A string **literal**. `\(...)` is supported when each interpolation is
///     itself a static string literal (not a variable). The whole value cannot be a variable.
///   - methods: An array literal of ``ObfuscationMethod`` values applied in order.
/// - Returns: The decoded `String` at runtime.
@freestanding(expression)
public macro Obfuscated(
    _ string: String,
    methods: [ObfuscationMethod]
) -> String = #externalMacro(module: "ObfuscatedMacros", type: "ObfuscatedMacro")
