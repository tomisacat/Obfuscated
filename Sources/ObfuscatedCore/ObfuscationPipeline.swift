import Foundation

/// Encode and decode pipeline for obfuscated string payloads.
///
/// Methods are applied forward during ``encode(_:methods:)`` and reversed during
/// ``decode(_:methods:)``. Crypto methods append a ``CryptoEntry`` to ``EncodedPayload/material``
/// for each step.
///
/// Used by the macro plugin at compile time and by ``ObfuscatedRuntime`` at runtime.
public enum ObfuscationPipeline {
    /// Encodes plaintext bytes through the given obfuscation methods.
    public static func encode(bytes: [UInt8], methods: [ObfuscationMethod]) throws -> EncodedPayload {
        try methods.forEach { try $0.validate() }

        var payload = EncodedPayload(bytes: bytes)

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
            case .custom(let id, let parameters):
                guard let step = ObfuscationStepRegistry.step(for: id) else {
                    throw ObfuscationError.unknownCustomStep(id)
                }
                payload.bytes = try step.encode(
                    bytes: payload.bytes,
                    parameters: parameters,
                    material: &payload.material
                )
            }
        }

        return payload
    }

    /// Encodes any ``ObfuscatedValue`` through the given obfuscation methods.
    public static func encode<T: ObfuscatedValue>(_ value: T, methods: [ObfuscationMethod]) throws -> EncodedPayload {
        let bytes = try T.plaintextBytes(from: value)
        return try encode(bytes: bytes, methods: methods)
    }

    /// Encodes a plaintext string through the given obfuscation methods.
    public static func encode(_ string: String, methods: [ObfuscationMethod]) throws -> EncodedPayload {
        let bytes = try String.plaintextBytes(from: string)
        return try encode(bytes: bytes, methods: methods)
    }

    /// Decodes obfuscated bytes by reversing the method chain.
    public static func decodeBytes(_ payload: EncodedPayload, methods: [ObfuscationMethod]) throws -> [UInt8] {
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
            case .custom(let id, let parameters):
                guard let step = ObfuscationStepRegistry.step(for: id) else {
                    throw ObfuscationError.unknownCustomStep(id)
                }
                bytes = try step.decode(
                    bytes: bytes,
                    parameters: parameters,
                    material: &material
                )
            }
        }

        return bytes
    }

    /// Decodes an ``EncodedPayload`` into any ``ObfuscatedValue`` type.
    public static func decode<T: ObfuscatedValue>(
        _ payload: EncodedPayload,
        methods: [ObfuscationMethod],
        as type: T.Type = T.self
    ) throws -> T {
        let bytes = try decodeBytes(payload, methods: methods)
        return try T.value(fromPlaintextBytes: bytes)
    }

    /// Encodes a ``RawRepresentable`` value through the given obfuscation methods.
    public static func encode<R: RawRepresentable>(
        _ value: R,
        methods: [ObfuscationMethod]
    ) throws -> EncodedPayload where R.RawValue: ObfuscatedValue {
        let bytes = try ObfuscatedRawRepresentableSupport.plaintextBytes(from: value)
        return try encode(bytes: bytes, methods: methods)
    }

    /// Decodes an ``EncodedPayload`` into a ``RawRepresentable`` type.
    public static func decode<R: RawRepresentable>(
        _ payload: EncodedPayload,
        methods: [ObfuscationMethod],
        as type: R.Type
    ) throws -> R where R.RawValue: ObfuscatedValue {
        let bytes = try decodeBytes(payload, methods: methods)
        return try ObfuscatedRawRepresentableSupport.value(fromPlaintextBytes: bytes, as: type)
    }

    /// Decodes an ``EncodedPayload`` by reversing the method chain.
    public static func decode(_ payload: EncodedPayload, methods: [ObfuscationMethod]) throws -> String {
        try decode(payload, methods: methods, as: String.self)
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
