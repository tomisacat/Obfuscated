import Foundation

/// Identifies the crypto scheme stored in a ``CryptoEntry``.
public enum CryptoAlgorithm: String, Sendable, Equatable {
    /// AES-GCM authenticated encryption.
    case aesGCM
    /// ChaCha20-Poly1305 authenticated encryption.
    case chaChaPoly
    /// HMAC-SHA256 keystream obfuscation.
    case hmacSHA256
    /// HMAC-SHA384 keystream obfuscation.
    case hmacSHA384
    /// HMAC-SHA512 keystream obfuscation.
    case hmacSHA512
    /// HKDF-SHA256 derivation followed by AES-GCM.
    case hkdfAESGCM
    /// HKDF-SHA256 derivation followed by ChaCha20-Poly1305.
    case hkdfChaChaPoly
    /// Curve25519 ECDH + HKDF + AES-GCM (ECIES-style).
    case curve25519AESGCM
    /// P-256 ECDH + HKDF + AES-GCM (ECIES-style).
    case p256AESGCM
}

/// Persisted state for one crypto step, embedded in macro expansions.
///
/// Sensitive byte arrays (`primary`, `secondary`, `tertiary`) are XOR-masked with single-byte masks.
public struct CryptoEntry: Sendable, Equatable {
    /// The crypto scheme used to produce this entry.
    public let algorithm: CryptoAlgorithm
    /// Ciphertext or obfuscated payload bytes for this step.
    public let payload: [UInt8]
    /// Masked primary secret (key, input key, or recipient private key).
    public let primary: [UInt8]
    /// Masked secondary secret (salt or unused bytes).
    public let secondary: [UInt8]
    /// Masked tertiary secret (HKDF info or ephemeral public key bytes).
    public let tertiary: [UInt8]
    /// Single-byte XOR mask for ``primary``.
    public let primaryMask: UInt8
    /// Single-byte XOR mask for ``secondary``.
    public let secondaryMask: UInt8
    /// Single-byte XOR mask for ``tertiary``.
    public let tertiaryMask: UInt8

    /// Creates a crypto entry with pre-masked secret byte arrays.
    public init(
        algorithm: CryptoAlgorithm,
        payload: [UInt8],
        primary: [UInt8],
        secondary: [UInt8],
        tertiary: [UInt8] = [],
        primaryMask: UInt8,
        secondaryMask: UInt8,
        tertiaryMask: UInt8 = 0
    ) {
        self.algorithm = algorithm
        self.payload = payload
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.primaryMask = primaryMask
        self.secondaryMask = secondaryMask
        self.tertiaryMask = tertiaryMask
    }

    /// Reveals the primary secret by XOR-unmasking ``primary`` with ``primaryMask``.
    func unmaskedPrimary() -> [UInt8] {
        primary.map { $0 ^ primaryMask }
    }

    /// Reveals the secondary secret by XOR-unmasking ``secondary`` with ``secondaryMask``.
    func unmaskedSecondary() -> [UInt8] {
        secondary.map { $0 ^ secondaryMask }
    }

    /// Reveals the tertiary secret by XOR-unmasking ``tertiary`` with ``tertiaryMask``.
    func unmaskedTertiary() -> [UInt8] {
        tertiary.map { $0 ^ tertiaryMask }
    }
}

/// Ordered stack of ``CryptoEntry`` values — one per crypto method in the pipeline.
public struct CryptoMaterial: Sendable, Equatable {
    /// Crypto entries appended in encode order and popped in reverse during decode.
    public var entries: [CryptoEntry]
    /// Custom step entries appended in encode order and popped in reverse during decode.
    public var customEntries: [CustomMaterialEntry]

    /// Creates crypto material, optionally seeded with existing entries.
    ///
    /// - Parameters:
    ///   - entries: Initial crypto entry stack (empty for lightweight-only pipelines).
    ///   - customEntries: Initial custom step material stack.
    public init(entries: [CryptoEntry] = [], customEntries: [CustomMaterialEntry] = []) {
        self.entries = entries
        self.customEntries = customEntries
    }
}

/// Wire format between ``ObfuscationPipeline/encode(_:methods:)`` and ``decode(_:methods:)``.
public struct EncodedPayload: Sendable, Equatable {
    /// Current obfuscated byte array after all applied transforms.
    public var bytes: [UInt8]
    /// Accumulated crypto entries for crypto pipeline steps.
    public var material: CryptoMaterial

    /// Creates an encoded payload from bytes and optional crypto material.
    ///
    /// - Parameters:
    ///   - bytes: Obfuscated bytes.
    ///   - material: Crypto entries collected during encoding.
    public init(bytes: [UInt8], material: CryptoMaterial = CryptoMaterial()) {
        self.bytes = bytes
        self.material = material
    }
}

/// Cryptographically secure random byte generation, with a deterministic test mode.
enum SecureRandom {
    /// When `true`, ``byte()`` and ``bytes(count:)`` return fixed `0x5A` bytes for reproducible tests.
    nonisolated(unsafe) static var useDeterministicValuesForTesting = false

    /// Generates a single random byte using `SecRandomCopyBytes`.
    ///
    /// - Returns: One random byte, or `0x5A` in deterministic test mode.
    static func byte() -> UInt8 {
        if useDeterministicValuesForTesting {
            return 0x5A
        }
        var value: UInt8 = 0
        _ = withUnsafeMutableBytes(of: &value) { SecRandomCopyBytes(kSecRandomDefault, 1, $0.baseAddress!) }
        return value
    }

    /// Generates a random byte array of the requested length.
    ///
    /// - Parameter count: Number of bytes to generate.
    /// - Returns: Random bytes, or repeated `0x5A` in deterministic test mode.
    static func bytes(count: Int) -> [UInt8] {
        if useDeterministicValuesForTesting {
            return Array(repeating: 0x5A, count: count)
        }
        var buffer = [UInt8](repeating: 0, count: count)
        _ = buffer.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return buffer
    }
}

/// Builds XOR-masked ``CryptoEntry`` values so secrets are not stored verbatim in expansions.
enum MaskedStorage {
    /// XOR-masks a byte array with a freshly generated random mask byte.
    ///
    /// - Parameter bytes: Secret bytes to mask.
    /// - Returns: Masked bytes and the mask used.
    static func mask(_ bytes: [UInt8]) -> (masked: [UInt8], mask: UInt8) {
        let mask = SecureRandom.byte()
        return (bytes.map { $0 ^ mask }, mask)
    }

    /// Creates a fully masked ``CryptoEntry`` for a crypto pipeline step.
    ///
    /// - Parameters:
    ///   - algorithm: Crypto scheme identifier.
    ///   - payload: Ciphertext or obfuscated output bytes.
    ///   - primary: Primary secret (e.g. symmetric key or private key).
    ///   - secondary: Secondary secret (e.g. salt), defaulting to empty.
    ///   - tertiary: Tertiary secret (e.g. HKDF info or ephemeral public key), defaulting to empty.
    /// - Returns: A ``CryptoEntry`` with masked secret fields.
    static func entry(
        algorithm: CryptoAlgorithm,
        payload: [UInt8],
        primary: [UInt8],
        secondary: [UInt8] = [],
        tertiary: [UInt8] = []
    ) -> CryptoEntry {
        let maskedPrimary = mask(primary)
        let maskedSecondary = mask(secondary)
        let maskedTertiary = mask(tertiary)
        return CryptoEntry(
            algorithm: algorithm,
            payload: payload,
            primary: maskedPrimary.masked,
            secondary: maskedSecondary.masked,
            tertiary: maskedTertiary.masked,
            primaryMask: maskedPrimary.mask,
            secondaryMask: maskedSecondary.mask,
            tertiaryMask: maskedTertiary.mask
        )
    }
}
