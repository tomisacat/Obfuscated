import Foundation

/// Encode and decode pipeline for obfuscated string payloads.
///
/// Methods are applied forward during ``encode(_:methods:)`` and reversed during
/// ``decode(_:methods:)``. Crypto methods append a ``CryptoEntry`` to ``EncodedPayload/material``
/// for each step.
///
/// Used by the macro plugin at compile time and by ``ObfuscatedRuntime`` at runtime.
public enum ObfuscationPipeline {
    /// Encodes a plaintext string through the given obfuscation methods.
    ///
    /// - Parameters:
    ///   - string: UTF-8 plaintext.
    ///   - methods: Ordered list of transforms (see ``ObfuscationMethod``).
    /// - Returns: Obfuscated bytes and any accumulated crypto material.
    public static func encode(_ string: String, methods: [ObfuscationMethod]) throws -> EncodedPayload {
        try methods.forEach { try $0.validate() }

        guard let utf8 = string.data(using: .utf8) else {
            throw ObfuscationError.decodingFailed("Unable to encode string as UTF-8")
        }

        var payload = EncodedPayload(bytes: Array(utf8))

        for method in methods {
            switch method {
            case .xor(let key):
                payload.bytes = BitwiseObfuscator.xor(payload.bytes, key: key)
            case .bitShift(let amount):
                payload.bytes = BitwiseObfuscator.rotateLeft(payload.bytes, by: amount)
            case .bitOr(let mask):
                guard payload.bytes.allSatisfy({ ($0 & mask) == 0 }) else {
                    throw ObfuscationError.decodingFailed("bitOr mask overlaps existing bits in plaintext")
                }
                payload.bytes = BitwiseObfuscator.bitOr(payload.bytes, mask: mask)
            case .base64:
                payload.bytes = Base64Obfuscator.encode(payload.bytes)
            case .aesGCM, .chaChaPoly, .chacha20,
                 .hmacSHA256, .hmacSHA384, .hmacSHA512,
                 .hkdfAESGCM, .hkdfChaChaPoly,
                 .curve25519AESGCM, .p256AESGCM:
                let result = try CryptoObfuscator.encrypt(payload.bytes, method: method)
                payload.bytes = result.payload
                payload.material.entries.append(result.entry)
            }
        }

        return payload
    }

    /// Decodes an ``EncodedPayload`` by reversing the method chain.
    ///
    /// - Parameters:
    ///   - payload: Obfuscated bytes and crypto material from encode (or macro expansion).
    ///   - methods: Same method list used during encoding, in the same order.
    /// - Returns: The original plaintext string.
    public static func decode(_ payload: EncodedPayload, methods: [ObfuscationMethod]) throws -> String {
        try methods.forEach { try $0.validate() }

        var bytes = payload.bytes
        var material = payload.material

        for method in methods.reversed() {
            switch method {
            case .xor(let key):
                bytes = BitwiseObfuscator.xor(bytes, key: key)
            case .bitShift(let amount):
                bytes = BitwiseObfuscator.rotateRight(bytes, by: amount)
            case .bitOr(let mask):
                bytes = bytes.map { $0 & ~mask }
            case .base64:
                bytes = try Base64Obfuscator.decode(bytes)
            case .aesGCM, .chaChaPoly, .chacha20,
                 .hmacSHA256, .hmacSHA384, .hmacSHA512,
                 .hkdfAESGCM, .hkdfChaChaPoly,
                 .curve25519AESGCM, .p256AESGCM:
                guard let entry = material.entries.popLast() else {
                    throw ObfuscationError.missingCryptoMaterial(cryptoMaterialLabel(for: method))
                }
                bytes = try CryptoObfuscator.decrypt(bytes, entry: entry)
            }
        }

        guard let string = String(bytes: bytes, encoding: .utf8) else {
            throw ObfuscationError.decodingFailed("Unable to decode bytes as UTF-8")
        }
        return string
    }

    /// Returns a stable method name for ``ObfuscationError/missingCryptoMaterial(_:)`` diagnostics.
    private static func cryptoMaterialLabel(for method: ObfuscationMethod) -> String {
        switch method {
        case .aesGCM: "aesGCM"
        case .chaChaPoly: "chaChaPoly"
        case .chacha20: "chacha20"
        case .hmacSHA256: "hmacSHA256"
        case .hmacSHA384: "hmacSHA384"
        case .hmacSHA512: "hmacSHA512"
        case .hkdfAESGCM: "hkdfAESGCM"
        case .hkdfChaChaPoly: "hkdfChaChaPoly"
        case .curve25519AESGCM: "curve25519AESGCM"
        case .p256AESGCM: "p256AESGCM"
        default: "crypto"
        }
    }
}
