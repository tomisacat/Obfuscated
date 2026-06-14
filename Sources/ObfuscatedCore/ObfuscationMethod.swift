import Foundation

/// Explicit symmetric key bytes for crypto obfuscation methods.
///
/// Pass to ``ObfuscationMethod/aesGCM(key:nonce:)``, ``ObfuscationMethod/chaChaPoly(key:nonce:)``,
/// HMAC methods, HKDF methods, or ECIES methods. Use `nil` to generate a random key at compile time.
public struct ObfuscatedKey: Sendable, Equatable {
    /// Raw key material. Length requirements depend on the chosen ``ObfuscationMethod``.
    public let bytes: [UInt8]

    /// Creates a key wrapper from explicit byte values.
    ///
    /// - Parameter bytes: Key bytes matching the target algorithm (e.g. 16 or 32 for AES-GCM).
    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }
}

/// Explicit nonce bytes for AEAD methods (12 bytes when provided).
public struct ObfuscatedNonce: Sendable, Equatable {
    /// Raw nonce bytes. Must be exactly 12 bytes when non-`nil`.
    public let bytes: [UInt8]

    /// Creates a nonce wrapper from explicit byte values.
    ///
    /// - Parameter bytes: Nonce bytes (typically 12 for AES-GCM and ChaCha20-Poly1305).
    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }
}

/// Explicit salt bytes for HMAC and HKDF methods.
public struct ObfuscatedSalt: Sendable, Equatable {
    /// Raw salt bytes used as HKDF/HMAC input material.
    public let bytes: [UInt8]

    /// Creates a salt wrapper from explicit byte values.
    ///
    /// - Parameter bytes: Salt bytes. Random bytes are generated at encode time when `nil` is passed to the method.
    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }
}

/// Explicit HKDF info bytes for ``ObfuscationMethod/hkdfAESGCM(inputKey:salt:info:nonce:)``
/// and ``ObfuscationMethod/hkdfChaChaPoly(inputKey:salt:info:nonce:)``.
public struct ObfuscatedInfo: Sendable, Equatable {
    /// Raw HKDF `info` parameter bytes.
    public let bytes: [UInt8]

    /// Creates an info wrapper from explicit byte values.
    ///
    /// - Parameter bytes: Context-binding info bytes for HKDF derivation.
    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }
}

/// A single obfuscation transform in an encode/decode pipeline.
///
/// Lightweight methods (xor, bitShift, bitOr, base64) operate on raw bytes.
/// Crypto methods use CryptoKit and store masked key material in ``CryptoMaterial``.
///
/// Chain multiple methods in array order: `[.xor(key: 0x5A), .aesGCM(key: nil, nonce: nil), .base64]`.
public enum ObfuscationMethod: Sendable, Equatable {
    /// XOR every byte with a constant key. Self-inverse.
    case xor(key: UInt8)
    /// Rotate each byte left by `amount` bits (1…7). Reversed with rotate-right on decode.
    case bitShift(by: Int)
    /// OR a mask into each byte. Mask bits must be clear in the plaintext at encode time.
    case bitOr(mask: UInt8)
    /// Base64-encode bytes as ASCII.
    case base64

    /// AES-GCM authenticated encryption. Key: 16/32 bytes or `nil`; nonce: 12 bytes or `nil`.
    case aesGCM(key: ObfuscatedKey?, nonce: ObfuscatedNonce?)
    /// ChaCha20-Poly1305 authenticated encryption. Key: 32 bytes or `nil`; nonce: 12 bytes or `nil`.
    case chaChaPoly(key: ObfuscatedKey?, nonce: ObfuscatedNonce?)
    /// Alias for ``chaChaPoly(key:nonce:)``.
    case chacha20(key: ObfuscatedKey?, nonce: ObfuscatedNonce?)

    /// HMAC-SHA256 keystream XOR. Key and salt default to random bytes when `nil`.
    case hmacSHA256(key: ObfuscatedKey?, salt: ObfuscatedSalt?)
    /// HMAC-SHA384 keystream XOR.
    case hmacSHA384(key: ObfuscatedKey?, salt: ObfuscatedSalt?)
    /// HMAC-SHA512 keystream XOR.
    case hmacSHA512(key: ObfuscatedKey?, salt: ObfuscatedSalt?)

    /// HKDF-SHA256 key derivation followed by AES-GCM.
    case hkdfAESGCM(
        inputKey: ObfuscatedKey?,
        salt: ObfuscatedSalt?,
        info: ObfuscatedInfo?,
        nonce: ObfuscatedNonce?
    )
    /// HKDF-SHA256 key derivation followed by ChaCha20-Poly1305.
    case hkdfChaChaPoly(
        inputKey: ObfuscatedKey?,
        salt: ObfuscatedSalt?,
        info: ObfuscatedInfo?,
        nonce: ObfuscatedNonce?
    )

    /// Curve25519 ECDH + HKDF + AES-GCM (ECIES-style).
    case curve25519AESGCM(recipientPrivateKey: ObfuscatedKey?, nonce: ObfuscatedNonce?)
    /// P-256 ECDH + HKDF + AES-GCM (ECIES-style).
    case p256AESGCM(recipientPrivateKey: ObfuscatedKey?, nonce: ObfuscatedNonce?)

    /// User-defined step registered via ``ObfuscationStepRegistry``.
    case custom(id: String, parameters: ObfuscationParameters)
}

/// Errors thrown by ``ObfuscationPipeline`` during encode or decode.
public enum ObfuscationError: Error, Equatable, Sendable {
    /// ``ObfuscationMethod/bitShift(by:)`` received an amount outside `1…7`.
    case invalidShiftAmount(Int)
    /// AES-GCM key is not 16 or 32 bytes.
    case invalidAESKeySize(Int)
    /// ChaCha20-Poly1305 key is not 32 bytes.
    case invalidChaChaKeySize(Int)
    /// ChaCha20-Poly1305 nonce is not 12 bytes.
    case invalidChaChaNonceSize(Int)
    /// HMAC key byte array is empty.
    case invalidHMACKeySize(Int)
    /// HKDF input key byte array is empty.
    case invalidHKDFInputKeySize(Int)
    /// Curve25519 private key is not 32 bytes.
    case invalidCurve25519PrivateKeySize(Int)
    /// P-256 private key is not 32 bytes.
    case invalidP256PrivateKeySize(Int)
    /// Base64 decode failed because the payload is not valid UTF-8 or Base64.
    case invalidBase64Payload
    /// Decode expected a ``CryptoEntry`` for a crypto method but the material stack was empty.
    case missingCryptoMaterial(String)
    /// CryptoKit is unavailable on the current platform.
    case cryptoUnavailable
    /// A general encode/decode failure with a descriptive message.
    case decodingFailed(String)
    /// No registered ``ObfuscationStep`` matches the custom method identifier.
    case unknownCustomStep(String)
    /// Decode expected custom material but the stack was empty.
    case missingCustomMaterial
}

extension ObfuscationMethod {
    /// Validates parameter sizes and value ranges for this method.
    ///
    /// Called by ``ObfuscationPipeline`` before encode and decode. Throws ``ObfuscationError``
    /// when key lengths, shift amounts, or nonce sizes are invalid.
    func validate() throws {
        switch self {
        case .xor, .bitOr, .base64:
            return
        case .bitShift(let amount):
            guard (1 ... 7).contains(amount) else {
                throw ObfuscationError.invalidShiftAmount(amount)
            }
        case .aesGCM(let key, let nonce):
            try validateAESKey(key)
            try validateAESNonce(nonce)
        case .chaChaPoly(let key, let nonce), .chacha20(let key, let nonce):
            try validateChaChaKey(key)
            try validateChaChaNonce(nonce)
        case .hmacSHA256(let key, _), .hmacSHA384(let key, _), .hmacSHA512(let key, _):
            if let key {
                guard !key.bytes.isEmpty else {
                    throw ObfuscationError.invalidHMACKeySize(0)
                }
            }
        case .hkdfAESGCM(let inputKey, _, _, let nonce):
            try validateHKDFInputKey(inputKey)
            try validateAESNonce(nonce)
        case .hkdfChaChaPoly(let inputKey, _, _, let nonce):
            try validateHKDFInputKey(inputKey)
            try validateChaChaNonce(nonce)
        case .curve25519AESGCM(let privateKey, let nonce):
            try validateCurve25519PrivateKey(privateKey)
            try validateAESNonce(nonce)
        case .p256AESGCM(let privateKey, let nonce):
            try validateP256PrivateKey(privateKey)
            try validateAESNonce(nonce)
        case .custom(let id, let parameters):
            guard let step = ObfuscationStepRegistry.step(for: id) else {
                throw ObfuscationError.unknownCustomStep(id)
            }
            try step.validate(parameters: parameters)
        }
    }

    /// Ensures an explicit AES key is 128- or 256-bit when provided.
    private func validateAESKey(_ key: ObfuscatedKey?) throws {
        if let key {
            guard key.bytes.count == 16 || key.bytes.count == 32 else {
                throw ObfuscationError.invalidAESKeySize(key.bytes.count)
            }
        }
    }

    /// Ensures an explicit AES-GCM nonce is 12 bytes when provided.
    private func validateAESNonce(_ nonce: ObfuscatedNonce?) throws {
        if let nonce {
            guard nonce.bytes.count == 12 else {
                throw ObfuscationError.decodingFailed("AES-GCM nonce must be 12 bytes")
            }
        }
    }

    /// Ensures an explicit ChaCha20 key is 32 bytes when provided.
    private func validateChaChaKey(_ key: ObfuscatedKey?) throws {
        if let key {
            guard key.bytes.count == 32 else {
                throw ObfuscationError.invalidChaChaKeySize(key.bytes.count)
            }
        }
    }

    /// Ensures an explicit ChaCha20-Poly1305 nonce is 12 bytes when provided.
    private func validateChaChaNonce(_ nonce: ObfuscatedNonce?) throws {
        if let nonce {
            guard nonce.bytes.count == 12 else {
                throw ObfuscationError.invalidChaChaNonceSize(nonce.bytes.count)
            }
        }
    }

    /// Ensures an explicit HKDF input key is non-empty when provided.
    private func validateHKDFInputKey(_ key: ObfuscatedKey?) throws {
        if let key {
            guard !key.bytes.isEmpty else {
                throw ObfuscationError.invalidHKDFInputKeySize(0)
            }
        }
    }

    /// Ensures an explicit Curve25519 private key is 32 bytes when provided.
    private func validateCurve25519PrivateKey(_ key: ObfuscatedKey?) throws {
        if let key {
            guard key.bytes.count == 32 else {
                throw ObfuscationError.invalidCurve25519PrivateKeySize(key.bytes.count)
            }
        }
    }

    /// Ensures an explicit P-256 private key is 32 bytes when provided.
    private func validateP256PrivateKey(_ key: ObfuscatedKey?) throws {
        if let key {
            guard key.bytes.count == 32 else {
                throw ObfuscationError.invalidP256PrivateKeySize(key.bytes.count)
            }
        }
    }
}

extension ObfuscationMethod {
    /// Returns the ``CryptoAlgorithm`` tag for crypto methods, or `nil` for lightweight transforms.
    var cryptoAlgorithm: CryptoAlgorithm? {
        switch self {
        case .aesGCM:
            return .aesGCM
        case .chaChaPoly, .chacha20:
            return .chaChaPoly
        case .hmacSHA256:
            return .hmacSHA256
        case .hmacSHA384:
            return .hmacSHA384
        case .hmacSHA512:
            return .hmacSHA512
        case .hkdfAESGCM:
            return .hkdfAESGCM
        case .hkdfChaChaPoly:
            return .hkdfChaChaPoly
        case .curve25519AESGCM:
            return .curve25519AESGCM
        case .p256AESGCM:
            return .p256AESGCM
        default:
            return nil
        }
    }
}
