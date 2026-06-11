import CryptoKit
import Foundation

/// CryptoKit-backed encrypt and decrypt operations for crypto ``ObfuscationMethod`` cases.
enum CryptoObfuscator {
    /// Encrypts bytes using the specified crypto ``ObfuscationMethod``.
    ///
    /// - Parameters:
    ///   - bytes: Plaintext bytes at the current pipeline stage.
    ///   - method: A crypto obfuscation method case.
    /// - Returns: The ciphertext (or obfuscated payload) and a masked ``CryptoEntry`` for decode.
    /// - Throws: ``ObfuscationError`` when parameters are invalid or encryption fails.
    static func encrypt(_ bytes: [UInt8], method: ObfuscationMethod) throws -> (payload: [UInt8], entry: CryptoEntry) {
        switch method {
        case .aesGCM(let key, let nonce):
            return try encryptAESGCM(bytes, key: key, nonce: nonce, algorithm: .aesGCM)
        case .chaChaPoly(let key, let nonce), .chacha20(let key, let nonce):
            return try encryptChaChaPoly(bytes, key: key, nonce: nonce, algorithm: .chaChaPoly)
        case .hmacSHA256(let key, let salt):
            return try encryptHMAC(bytes, key: key, salt: salt, algorithm: .hmacSHA256)
        case .hmacSHA384(let key, let salt):
            return try encryptHMAC(bytes, key: key, salt: salt, algorithm: .hmacSHA384)
        case .hmacSHA512(let key, let salt):
            return try encryptHMAC(bytes, key: key, salt: salt, algorithm: .hmacSHA512)
        case .hkdfAESGCM(let inputKey, let salt, let info, let nonce):
            return try encryptHKDFAESGCM(bytes, inputKey: inputKey, salt: salt, info: info, nonce: nonce)
        case .hkdfChaChaPoly(let inputKey, let salt, let info, let nonce):
            return try encryptHKDFChaChaPoly(bytes, inputKey: inputKey, salt: salt, info: info, nonce: nonce)
        case .curve25519AESGCM(let privateKey, let nonce):
            return try encryptCurve25519AESGCM(bytes, recipientPrivateKey: privateKey, nonce: nonce)
        case .p256AESGCM(let privateKey, let nonce):
            return try encryptP256AESGCM(bytes, recipientPrivateKey: privateKey, nonce: nonce)
        default:
            throw ObfuscationError.decodingFailed("Unsupported crypto method")
        }
    }

    /// Decrypts bytes using the algorithm and masked secrets stored in a ``CryptoEntry``.
    ///
    /// - Parameters:
    ///   - bytes: Ciphertext bytes (unused for some algorithms that read from the entry payload).
    ///   - entry: Persisted crypto state from the matching encode step.
    /// - Returns: Recovered plaintext bytes.
    /// - Throws: ``ObfuscationError`` when decryption or key derivation fails.
    static func decrypt(_ bytes: [UInt8], entry: CryptoEntry) throws -> [UInt8] {
        switch entry.algorithm {
        case .aesGCM:
            return try decryptAESGCM(entry: entry)
        case .chaChaPoly:
            return try decryptChaChaPoly(entry: entry)
        case .hmacSHA256:
            return try decryptHMAC(entry: entry, kind: .sha256)
        case .hmacSHA384:
            return try decryptHMAC(entry: entry, kind: .sha384)
        case .hmacSHA512:
            return try decryptHMAC(entry: entry, kind: .sha512)
        case .hkdfAESGCM:
            let derivedKey = try deriveSymmetricKey(
                inputKeyBytes: entry.unmaskedPrimary(),
                saltBytes: entry.unmaskedSecondary(),
                infoBytes: entry.unmaskedTertiary(),
                outputByteCount: 32
            )
            return try decryptAESGCM(entry: entry, symmetricKey: derivedKey)
        case .hkdfChaChaPoly:
            let derivedKey = try deriveSymmetricKey(
                inputKeyBytes: entry.unmaskedPrimary(),
                saltBytes: entry.unmaskedSecondary(),
                infoBytes: entry.unmaskedTertiary(),
                outputByteCount: 32
            )
            return try decryptChaChaPoly(entry: entry, symmetricKey: derivedKey)
        case .curve25519AESGCM:
            return try decryptECIES(entry: entry, curve: .curve25519)
        case .p256AESGCM:
            return try decryptECIES(entry: entry, curve: .p256)
        }
    }

    // MARK: - AES-GCM

    /// Encrypts with AES-GCM, generating random key/nonce material when not provided.
    private static func encryptAESGCM(
        _ bytes: [UInt8],
        key: ObfuscatedKey?,
        nonce: ObfuscatedNonce?,
        algorithm: CryptoAlgorithm
    ) throws -> (payload: [UInt8], entry: CryptoEntry) {
        let keyBytes = key?.bytes ?? SecureRandom.bytes(count: 16)
        guard keyBytes.count == 16 || keyBytes.count == 32 else {
            throw ObfuscationError.invalidAESKeySize(keyBytes.count)
        }
        let symmetricKey = SymmetricKey(data: Data(keyBytes))
        let sealedBox = try sealAES(bytes, using: symmetricKey, nonce: nonce)
        let entry = MaskedStorage.entry(
            algorithm: algorithm,
            payload: sealedBox,
            primary: keyBytes
        )
        return (sealedBox, entry)
    }

    /// Opens an AES-GCM sealed box using the entry's unmasked primary key or an override key.
    private static func decryptAESGCM(entry: CryptoEntry, symmetricKey: SymmetricKey? = nil) throws -> [UInt8] {
        let key = symmetricKey ?? SymmetricKey(data: Data(entry.unmaskedPrimary()))
        let sealedBox = try AES.GCM.SealedBox(combined: Data(entry.payload))
        return Array(try AES.GCM.open(sealedBox, using: key))
    }

    /// Seals bytes with AES-GCM and returns the combined nonce+ciphertext+tag representation.
    private static func sealAES(_ bytes: [UInt8], using key: SymmetricKey, nonce: ObfuscatedNonce?) throws -> [UInt8] {
        let nonceBytes = nonce?.bytes ?? SecureRandom.bytes(count: 12)
        guard nonceBytes.count == 12 else {
            throw ObfuscationError.decodingFailed("AES-GCM nonce must be 12 bytes")
        }
        let nonceValue = try AES.GCM.Nonce(data: Data(nonceBytes))
        let sealed = try AES.GCM.seal(Data(bytes), using: key, nonce: nonceValue)
        return Array(sealed.combined ?? Data())
    }

    // MARK: - ChaChaPoly

    /// Encrypts with ChaCha20-Poly1305, generating random key/nonce material when not provided.
    private static func encryptChaChaPoly(
        _ bytes: [UInt8],
        key: ObfuscatedKey?,
        nonce: ObfuscatedNonce?,
        algorithm: CryptoAlgorithm
    ) throws -> (payload: [UInt8], entry: CryptoEntry) {
        let keyBytes = key?.bytes ?? SecureRandom.bytes(count: 32)
        guard keyBytes.count == 32 else {
            throw ObfuscationError.invalidChaChaKeySize(keyBytes.count)
        }
        let symmetricKey = SymmetricKey(data: Data(keyBytes))
        let sealedBox = try sealChaChaPoly(bytes, using: symmetricKey, nonce: nonce)
        let entry = MaskedStorage.entry(
            algorithm: algorithm,
            payload: sealedBox,
            primary: keyBytes
        )
        return (sealedBox, entry)
    }

    /// Opens a ChaCha20-Poly1305 sealed box using the entry's unmasked primary key or an override key.
    private static func decryptChaChaPoly(entry: CryptoEntry, symmetricKey: SymmetricKey? = nil) throws -> [UInt8] {
        let key = symmetricKey ?? SymmetricKey(data: Data(entry.unmaskedPrimary()))
        let sealedBox = try ChaChaPoly.SealedBox(combined: Data(entry.payload))
        return Array(try ChaChaPoly.open(sealedBox, using: key))
    }

    /// Seals bytes with ChaCha20-Poly1305 and returns the combined sealed representation.
    private static func sealChaChaPoly(_ bytes: [UInt8], using key: SymmetricKey, nonce: ObfuscatedNonce?) throws -> [UInt8] {
        let nonceBytes = nonce?.bytes ?? SecureRandom.bytes(count: 12)
        guard nonceBytes.count == 12 else {
            throw ObfuscationError.invalidChaChaNonceSize(nonceBytes.count)
        }
        let nonceValue = try ChaChaPoly.Nonce(data: Data(nonceBytes))
        let sealed = try ChaChaPoly.seal(Data(bytes), using: key, nonce: nonceValue)
        return Array(sealed.combined)
    }

    // MARK: - HMAC keystream

    /// Selects the HMAC hash function for keystream generation.
    private enum HMACKind {
        case sha256
        case sha384
        case sha512
    }

    /// Obfuscates bytes by XORing with an HMAC-derived keystream.
    private static func encryptHMAC(
        _ bytes: [UInt8],
        key: ObfuscatedKey?,
        salt: ObfuscatedSalt?,
        algorithm: CryptoAlgorithm
    ) throws -> (payload: [UInt8], entry: CryptoEntry) {
        let keyBytes = key?.bytes ?? SecureRandom.bytes(count: 32)
        guard !keyBytes.isEmpty else {
            throw ObfuscationError.invalidHMACKeySize(0)
        }
        let saltBytes = salt?.bytes ?? SecureRandom.bytes(count: 16)
        let symmetricKey = SymmetricKey(data: Data(keyBytes))
        let kind: HMACKind
        switch algorithm {
        case .hmacSHA256: kind = .sha256
        case .hmacSHA384: kind = .sha384
        case .hmacSHA512: kind = .sha512
        default: throw ObfuscationError.decodingFailed("Unsupported HMAC algorithm")
        }

        let keystream = hmacKeystream(key: symmetricKey, salt: Data(saltBytes), length: bytes.count, kind: kind)
        let payload = zip(bytes, keystream).map { $0 ^ $1 }
        let entry = MaskedStorage.entry(
            algorithm: algorithm,
            payload: payload,
            primary: keyBytes,
            secondary: saltBytes
        )
        return (payload, entry)
    }

    /// Recovers plaintext by XORing the payload with the same HMAC-derived keystream.
    private static func decryptHMAC(entry: CryptoEntry, kind: HMACKind) throws -> [UInt8] {
        let symmetricKey = SymmetricKey(data: Data(entry.unmaskedPrimary()))
        let keystream = hmacKeystream(
            key: symmetricKey,
            salt: Data(entry.unmaskedSecondary()),
            length: entry.payload.count,
            kind: kind
        )
        return zip(entry.payload, keystream).map { $0 ^ $1 }
    }

    /// Expands HMAC output into a keystream of the requested length using a counter suffix.
    private static func hmacKeystream(key: SymmetricKey, salt: Data, length: Int, kind: HMACKind) -> [UInt8] {
        var stream: [UInt8] = []
        var counter: UInt32 = 0
        while stream.count < length {
            var input = salt
            withUnsafeBytes(of: counter.bigEndian) { input.append(contentsOf: $0) }
            let block: [UInt8]
            switch kind {
            case .sha256:
                block = Array(HMAC<SHA256>.authenticationCode(for: input, using: key))
            case .sha384:
                block = Array(HMAC<SHA384>.authenticationCode(for: input, using: key))
            case .sha512:
                block = Array(HMAC<SHA512>.authenticationCode(for: input, using: key))
            }
            stream.append(contentsOf: block)
            counter += 1
        }
        return Array(stream.prefix(length))
    }

    // MARK: - HKDF

    /// Derives a symmetric key with HKDF-SHA256 and encrypts with AES-GCM.
    private static func encryptHKDFAESGCM(
        _ bytes: [UInt8],
        inputKey: ObfuscatedKey?,
        salt: ObfuscatedSalt?,
        info: ObfuscatedInfo?,
        nonce: ObfuscatedNonce?
    ) throws -> (payload: [UInt8], entry: CryptoEntry) {
        let inputKeyBytes = inputKey?.bytes ?? SecureRandom.bytes(count: 32)
        let saltBytes = salt?.bytes ?? SecureRandom.bytes(count: 16)
        let infoBytes = info?.bytes ?? []
        let derivedKey = try deriveSymmetricKey(
            inputKeyBytes: inputKeyBytes,
            saltBytes: saltBytes,
            infoBytes: infoBytes,
            outputByteCount: 32
        )
        let sealedBox = try sealAES(bytes, using: derivedKey, nonce: nonce)
        let entry = MaskedStorage.entry(
            algorithm: .hkdfAESGCM,
            payload: sealedBox,
            primary: inputKeyBytes,
            secondary: saltBytes,
            tertiary: infoBytes
        )
        return (sealedBox, entry)
    }

    /// Derives a symmetric key with HKDF-SHA256 and encrypts with ChaCha20-Poly1305.
    private static func encryptHKDFChaChaPoly(
        _ bytes: [UInt8],
        inputKey: ObfuscatedKey?,
        salt: ObfuscatedSalt?,
        info: ObfuscatedInfo?,
        nonce: ObfuscatedNonce?
    ) throws -> (payload: [UInt8], entry: CryptoEntry) {
        let inputKeyBytes = inputKey?.bytes ?? SecureRandom.bytes(count: 32)
        let saltBytes = salt?.bytes ?? SecureRandom.bytes(count: 16)
        let infoBytes = info?.bytes ?? []
        let derivedKey = try deriveSymmetricKey(
            inputKeyBytes: inputKeyBytes,
            saltBytes: saltBytes,
            infoBytes: infoBytes,
            outputByteCount: 32
        )
        let sealedBox = try sealChaChaPoly(bytes, using: derivedKey, nonce: nonce)
        let entry = MaskedStorage.entry(
            algorithm: .hkdfChaChaPoly,
            payload: sealedBox,
            primary: inputKeyBytes,
            secondary: saltBytes,
            tertiary: infoBytes
        )
        return (sealedBox, entry)
    }

    /// Derives a ``SymmetricKey`` with HKDF-SHA256 from input key material, salt, and info bytes.
    private static func deriveSymmetricKey(
        inputKeyBytes: [UInt8],
        saltBytes: [UInt8],
        infoBytes: [UInt8],
        outputByteCount: Int
    ) throws -> SymmetricKey {
        guard !inputKeyBytes.isEmpty else {
            throw ObfuscationError.invalidHKDFInputKeySize(0)
        }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(inputKeyBytes)),
            salt: Data(saltBytes),
            info: Data(infoBytes),
            outputByteCount: outputByteCount
        )
    }

    // MARK: - ECIES

    /// Elliptic curve used for ECIES-style key agreement.
    private enum ECCurve {
        case curve25519
        case p256
    }

    /// Fixed Curve25519 recipient key used when deterministic test mode is enabled.
    private static let deterministicCurve25519RecipientKey = Data([
        128, 24, 244, 84, 21, 244, 214, 62, 183, 150, 30, 211, 197, 174, 72, 184,
        120, 28, 213, 23, 200, 119, 247, 8, 103, 89, 248, 188, 68, 214, 98, 115,
    ])
    /// Fixed Curve25519 ephemeral key used when deterministic test mode is enabled.
    private static let deterministicCurve25519EphemeralKey = Data([
        32, 217, 37, 125, 38, 195, 195, 206, 117, 252, 55, 113, 168, 255, 62, 40,
        247, 110, 149, 100, 119, 2, 163, 167, 175, 122, 83, 75, 136, 139, 11, 107,
    ])
    /// Fixed P-256 recipient key used when deterministic test mode is enabled.
    private static let deterministicP256RecipientKey = Data([
        133, 243, 49, 104, 156, 53, 88, 130, 186, 23, 5, 199, 6, 84, 170, 69,
        178, 231, 36, 5, 138, 241, 166, 158, 194, 228, 83, 108, 81, 3, 163, 70,
    ])
    /// Fixed P-256 ephemeral key used when deterministic test mode is enabled.
    private static let deterministicP256EphemeralKey = Data([
        157, 139, 19, 210, 86, 4, 122, 34, 64, 72, 252, 71, 187, 196, 153, 13,
        175, 225, 121, 211, 163, 171, 104, 11, 212, 173, 122, 52, 116, 192, 140, 54,
    ])

    /// Performs Curve25519 ECDH, derives an AES key with HKDF, and encrypts with AES-GCM.
    private static func encryptCurve25519AESGCM(
        _ bytes: [UInt8],
        recipientPrivateKey: ObfuscatedKey?,
        nonce: ObfuscatedNonce?
    ) throws -> (payload: [UInt8], entry: CryptoEntry) {
        let recipientBytes = recipientPrivateKey?.bytes
            ?? (SecureRandom.useDeterministicValuesForTesting
                ? Array(deterministicCurve25519RecipientKey)
                : SecureRandom.bytes(count: 32))
        guard recipientBytes.count == 32 else {
            throw ObfuscationError.invalidCurve25519PrivateKeySize(recipientBytes.count)
        }
        let recipientPrivate = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(recipientBytes))
        let ephemeralPrivate = try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: SecureRandom.useDeterministicValuesForTesting
                ? deterministicCurve25519EphemeralKey
                : Data(Curve25519.KeyAgreement.PrivateKey().rawRepresentation)
        )
        let sharedSecret = try ephemeralPrivate.sharedSecretFromKeyAgreement(with: recipientPrivate.publicKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data("Obfuscated.ECIES".utf8),
            outputByteCount: 32
        )
        let sealedBox = try sealAES(bytes, using: symmetricKey, nonce: nonce)
        let entry = MaskedStorage.entry(
            algorithm: .curve25519AESGCM,
            payload: sealedBox,
            primary: recipientBytes,
            tertiary: Array(ephemeralPrivate.publicKey.rawRepresentation)
        )
        return (sealedBox, entry)
    }

    /// Performs P-256 ECDH, derives an AES key with HKDF, and encrypts with AES-GCM.
    private static func encryptP256AESGCM(
        _ bytes: [UInt8],
        recipientPrivateKey: ObfuscatedKey?,
        nonce: ObfuscatedNonce?
    ) throws -> (payload: [UInt8], entry: CryptoEntry) {
        let recipientBytes = recipientPrivateKey?.bytes
            ?? (SecureRandom.useDeterministicValuesForTesting
                ? Array(deterministicP256RecipientKey)
                : SecureRandom.bytes(count: 32))
        guard recipientBytes.count == 32 else {
            throw ObfuscationError.invalidP256PrivateKeySize(recipientBytes.count)
        }
        let recipientPrivate = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(recipientBytes))
        let ephemeralPrivate = try P256.KeyAgreement.PrivateKey(
            rawRepresentation: SecureRandom.useDeterministicValuesForTesting
                ? deterministicP256EphemeralKey
                : Data(P256.KeyAgreement.PrivateKey().rawRepresentation)
        )
        let sharedSecret = try ephemeralPrivate.sharedSecretFromKeyAgreement(with: recipientPrivate.publicKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data("Obfuscated.ECIES".utf8),
            outputByteCount: 32
        )
        let sealedBox = try sealAES(bytes, using: symmetricKey, nonce: nonce)
        let entry = MaskedStorage.entry(
            algorithm: .p256AESGCM,
            payload: sealedBox,
            primary: recipientBytes,
            tertiary: Array(ephemeralPrivate.publicKey.x963Representation)
        )
        return (sealedBox, entry)
    }

    /// Decrypts an ECIES entry by recomputing the shared secret from recipient and ephemeral public keys.
    private static func decryptECIES(entry: CryptoEntry, curve: ECCurve) throws -> [UInt8] {
        let recipientBytes = entry.unmaskedPrimary()
        let ephemeralPublicBytes = entry.unmaskedTertiary()

        let symmetricKey: SymmetricKey
        switch curve {
        case .curve25519:
            let recipientPrivate = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(recipientBytes))
            let ephemeralPublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: Data(ephemeralPublicBytes))
            let sharedSecret = try recipientPrivate.sharedSecretFromKeyAgreement(with: ephemeralPublic)
            symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: Data(),
                sharedInfo: Data("Obfuscated.ECIES".utf8),
                outputByteCount: 32
            )
        case .p256:
            let recipientPrivate = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(recipientBytes))
            let ephemeralPublic = try P256.KeyAgreement.PublicKey(x963Representation: Data(ephemeralPublicBytes))
            let sharedSecret = try recipientPrivate.sharedSecretFromKeyAgreement(with: ephemeralPublic)
            symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: Data(),
                sharedInfo: Data("Obfuscated.ECIES".utf8),
                outputByteCount: 32
            )
        }

        return try decryptAESGCM(entry: entry, symmetricKey: symmetricKey)
    }
}
