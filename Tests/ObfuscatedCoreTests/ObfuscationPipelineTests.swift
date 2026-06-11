import CryptoKit
import ObfuscatedCore
import Testing

private func assertRoundTrip(_ string: String, methods: [ObfuscationMethod]) throws {
    let payload = try ObfuscationPipeline.encode(string, methods: methods)
    let decoded = try ObfuscationPipeline.decode(payload, methods: methods)
    #expect(decoded == string)
}

@Suite("Obfuscation pipeline")
struct ObfuscationPipelineTests {
    @Test func xorRoundTrip() throws {
        try assertRoundTrip("Hello, Obfuscated!", methods: [.xor(key: 0x5A)])
    }

    @Test func bitShiftRoundTrip() throws {
        try assertRoundTrip("Shifted bytes", methods: [.bitShift(by: 3)])
    }

    @Test func bitOrRoundTrip() throws {
        try assertRoundTrip("Safe OR text", methods: [.bitOr(mask: 0x80)])
    }

    @Test func base64RoundTrip() throws {
        try assertRoundTrip("Base64 payload", methods: [.base64])
    }

    @Test func unicodeRoundTrip() throws {
        try assertRoundTrip("Emoji: 🚀🔒", methods: [.xor(key: 0x2C), .base64])
    }

    @Test func emptyStringRoundTrip() throws {
        try assertRoundTrip("", methods: [.xor(key: 0x11)])
    }

    @Test func pipelineRoundTrip() throws {
        try assertRoundTrip(
            "Pipeline secret",
            methods: [.xor(key: 0x7E), .bitShift(by: 2), .base64]
        )
    }

    @Test func pairwiseLightweightPipelines() throws {
        let methods: [ObfuscationMethod] = [
            .xor(key: 0x3C),
            .bitShift(by: 4),
            .bitOr(mask: 0x80),
            .base64,
        ]

        for lhs in methods {
            for rhs in methods {
                if case .bitOr = lhs, case .bitOr = rhs {
                    continue
                }
                if case .bitOr = rhs {
                    try assertRoundTrip("Pairwise", methods: [rhs, lhs])
                } else {
                    try assertRoundTrip("Pairwise", methods: [lhs, rhs])
                }
            }
        }
    }

    @Test func aesRoundTripWithExplicitKey() throws {
        let key = ObfuscatedKey(bytes: Array(repeating: 0xAB, count: 16))
        let nonce = ObfuscatedNonce(bytes: Array(repeating: 0x10, count: 12))
        try assertRoundTrip("AES protected", methods: [.aesGCM(key: key, nonce: nonce)])
    }

    @Test func chaChaRoundTripWithExplicitKey() throws {
        let key = ObfuscatedKey(bytes: Array(repeating: 0xCD, count: 32))
        let nonce = ObfuscatedNonce(bytes: Array(repeating: 0x01, count: 12))
        try assertRoundTrip("ChaCha protected", methods: [.chaChaPoly(key: key, nonce: nonce)])
    }

    @Test func chacha20AliasRoundTrip() throws {
        try assertRoundTrip("Legacy alias", methods: [.chacha20(key: nil, nonce: nil)])
    }

    @Test func aesRoundTripWithGeneratedKey() throws {
        try assertRoundTrip("Generated AES key", methods: [.aesGCM(key: nil, nonce: nil)])
    }

    @Test func chaChaRoundTripWithGeneratedKey() throws {
        try assertRoundTrip("Generated ChaCha key", methods: [.chaChaPoly(key: nil, nonce: nil)])
    }

    @Test func hmacSHA256RoundTrip() throws {
        try assertRoundTrip("HMAC SHA256", methods: [.hmacSHA256(key: nil, salt: nil)])
    }

    @Test func hmacSHA384RoundTrip() throws {
        try assertRoundTrip("HMAC SHA384", methods: [.hmacSHA384(key: nil, salt: nil)])
    }

    @Test func hmacSHA512RoundTrip() throws {
        try assertRoundTrip("HMAC SHA512", methods: [.hmacSHA512(key: nil, salt: nil)])
    }

    @Test func hkdfAESGCMRoundTrip() throws {
        try assertRoundTrip("HKDF AES-GCM", methods: [.hkdfAESGCM(inputKey: nil, salt: nil, info: nil, nonce: nil)])
    }

    @Test func hkdfChaChaPolyRoundTrip() throws {
        try assertRoundTrip("HKDF ChaChaPoly", methods: [.hkdfChaChaPoly(inputKey: nil, salt: nil, info: nil, nonce: nil)])
    }

    @Test func curve25519AESGCMRoundTrip() throws {
        let privateKey = ObfuscatedKey(bytes: Array(Curve25519.KeyAgreement.PrivateKey().rawRepresentation))
        try assertRoundTrip("Curve25519 ECIES", methods: [.curve25519AESGCM(recipientPrivateKey: privateKey, nonce: nil)])
    }

    @Test func p256AESGCMRoundTrip() throws {
        let privateKey = ObfuscatedKey(bytes: Array(P256.KeyAgreement.PrivateKey().rawRepresentation))
        try assertRoundTrip("P256 ECIES", methods: [.p256AESGCM(recipientPrivateKey: privateKey, nonce: nil)])
    }

    @Test func cryptoPipelineRoundTrip() throws {
        try assertRoundTrip(
            "Crypto pipeline",
            methods: [.xor(key: 0x19), .aesGCM(key: nil, nonce: nil), .base64]
        )
    }

    @Test func invalidShiftAmountThrows() {
        let error = #expect(throws: ObfuscationError.self) {
            try ObfuscationPipeline.encode("x", methods: [.bitShift(by: 8)])
        }
        #expect(error == .invalidShiftAmount(8))
    }

    @Test func invalidAESKeySizeThrows() {
        let key = ObfuscatedKey(bytes: [1, 2, 3])
        let error = #expect(throws: ObfuscationError.self) {
            try ObfuscationPipeline.encode("x", methods: [.aesGCM(key: key, nonce: nil)])
        }
        #expect(error == .invalidAESKeySize(3))
    }

    @Test func invalidChaChaKeySizeThrows() {
        let key = ObfuscatedKey(bytes: Array(repeating: 1, count: 16))
        let error = #expect(throws: ObfuscationError.self) {
            try ObfuscationPipeline.encode("x", methods: [.chaChaPoly(key: key, nonce: nil)])
        }
        #expect(error == .invalidChaChaKeySize(16))
    }

    @Test func bitOrOverlapThrows() {
        let error = #expect(throws: ObfuscationError.self) {
            try ObfuscationPipeline.encode("A", methods: [.bitOr(mask: 0x40)])
        }
        guard case .decodingFailed(let message) = error else {
            Issue.record("Expected decodingFailed, got \(error)")
            return
        }
        #expect(message.contains("bitOr mask overlaps"))
    }
}

@Suite("Obfuscated runtime")
struct ObfuscatedRuntimeTests {
    @Test func decodeReturnsPlainString() throws {
        let payload = try ObfuscationPipeline.encode("Runtime decode", methods: [.xor(key: 0x22)])
        let decoded = ObfuscatedRuntime._decode(
            bytes: payload.bytes,
            methods: [.xor(key: 0x22)],
            material: payload.material
        )
        #expect(decoded == "Runtime decode")
    }
}
