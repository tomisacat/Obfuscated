/// Runtime decode entry used by generated macro expansions.
///
/// Do not call directly from application code. The ``Obfuscated(_:methods:)`` macro expands to
/// calls to ``_decode(bytes:methods:material:)``.
public enum ObfuscatedRuntime {
    /// Decodes an obfuscated payload produced at compile time.
    ///
    /// - Parameters:
    ///   - bytes: Obfuscated byte array from macro expansion.
    ///   - methods: Method descriptors matching the encode pipeline.
    ///   - material: Crypto material entries (one per crypto method in the pipeline).
    /// - Returns: The original plaintext string, or `""` if decoding fails in release builds.
    public static func _decode(
        bytes: [UInt8],
        methods: [ObfuscationMethod],
        material: CryptoMaterial
    ) -> String {
        do {
            let payload = EncodedPayload(bytes: bytes, material: material)
            return try ObfuscationPipeline.decode(payload, methods: methods)
        } catch {
            assertionFailure("Obfuscated string decode failed: \(error)")
            return ""
        }
    }
}
