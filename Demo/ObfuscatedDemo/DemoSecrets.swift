import Foundation
import ObfuscatedDemoKit

private enum DemoMaterial {
    static let aesKey = ObfuscatedKey(bytes: Array(repeating: 0xAB, count: 16))
    static let aesNonce = ObfuscatedNonce(bytes: Array(repeating: 0x10, count: 12))
    static let chachaKey = ObfuscatedKey(bytes: Array(repeating: 0xCD, count: 32))
    static let chachaNonce = ObfuscatedNonce(bytes: Array(repeating: 0x01, count: 12))
    static let hmacKey = ObfuscatedKey(bytes: Array(repeating: 0x42, count: 32))
    static let hmacSalt = ObfuscatedSalt(bytes: [0x73, 0x61, 0x6C, 0x74])
    static let hkdfInput = ObfuscatedKey(bytes: Array(repeating: 0x11, count: 32))
    static let hkdfSalt = ObfuscatedSalt(bytes: [0xDE, 0xAD, 0xBE, 0xEF])
    static let hkdfInfo = ObfuscatedInfo(bytes: Array("Obfuscated.Demo".utf8))
    static let hkdfNonce = ObfuscatedNonce(bytes: Array(repeating: 0x22, count: 12))
    static let curve25519Recipient = ObfuscatedKey(bytes: [
        128, 24, 244, 84, 21, 244, 214, 62, 183, 150, 30, 211, 197, 174, 72, 184,
        120, 28, 213, 23, 200, 119, 247, 8, 103, 89, 248, 188, 68, 214, 98, 115,
    ])
    static let p256Recipient = ObfuscatedKey(bytes: [
        133, 243, 49, 104, 156, 53, 88, 130, 186, 23, 5, 199, 6, 84, 170, 69,
        178, 231, 36, 5, 138, 241, 166, 158, 194, 228, 83, 108, 81, 3, 163, 70,
    ])
}

enum DemoSecrets {
    static let xorSecret = #Obfuscated("XOR protected secret", methods: [.xor(key: 0x5A)])
    static let shiftSecret = #Obfuscated("Bit-shift protected secret", methods: [.bitShift(by: 3)])
    static let orSecret = #Obfuscated("Bit-OR protected secret", methods: [.bitOr(mask: 0x80)])
    static let base64Secret = #Obfuscated("Base64 protected secret", methods: [.base64])
    static let aesSecret = #Obfuscated("AES protected secret", methods: [.aesGCM(key: nil, nonce: nil)])
    static let chachaSecret = #Obfuscated("ChaCha protected secret", methods: [.chaChaPoly(key: nil, nonce: nil)])
    static let hmacSecret = #Obfuscated("HMAC protected secret", methods: [.hmacSHA256(key: nil, salt: nil)])
    static let hmac384Secret = #Obfuscated("HMAC-SHA384 protected secret", methods: [.hmacSHA384(key: nil, salt: nil)])
    static let hmac512Secret = #Obfuscated("HMAC-SHA512 protected secret", methods: [.hmacSHA512(key: nil, salt: nil)])
    static let hkdfSecret = #Obfuscated("HKDF protected secret", methods: [.hkdfAESGCM(inputKey: nil, salt: nil, info: nil, nonce: nil)])
    static let hkdfChaChaSecret = #Obfuscated("HKDF ChaCha protected secret", methods: [.hkdfChaChaPoly(inputKey: nil, salt: nil, info: nil, nonce: nil)])
    static let curve25519Secret = #Obfuscated("Curve25519 ECIES protected secret", methods: [.curve25519AESGCM(recipientPrivateKey: nil, nonce: nil)])
    static let p256Secret = #Obfuscated("P256 ECIES protected secret", methods: [.p256AESGCM(recipientPrivateKey: nil, nonce: nil)])

    static let explicitAESSecret = #Obfuscated(
        "AES with explicit key + nonce",
        methods: [.aesGCM(key: DemoMaterial.aesKey, nonce: DemoMaterial.aesNonce)]
    )
    static let explicitChaChaSecret = #Obfuscated(
        "ChaCha with explicit key + nonce",
        methods: [.chaChaPoly(key: DemoMaterial.chachaKey, nonce: DemoMaterial.chachaNonce)]
    )
    static let explicitHMACSecret = #Obfuscated(
        "HMAC with explicit key + salt",
        methods: [.hmacSHA256(key: DemoMaterial.hmacKey, salt: DemoMaterial.hmacSalt)]
    )
    static let explicitHKDFSecret = #Obfuscated(
        "HKDF with explicit input, salt, info, nonce",
        methods: [
            .hkdfAESGCM(
                inputKey: DemoMaterial.hkdfInput,
                salt: DemoMaterial.hkdfSalt,
                info: DemoMaterial.hkdfInfo,
                nonce: DemoMaterial.hkdfNonce
            ),
        ]
    )
    static let explicitCurve25519Secret = #Obfuscated(
        "Curve25519 with explicit recipient key",
        methods: [.curve25519AESGCM(recipientPrivateKey: DemoMaterial.curve25519Recipient, nonce: nil)]
    )
    static let explicitP256Secret = #Obfuscated(
        "P256 with explicit recipient key",
        methods: [.p256AESGCM(recipientPrivateKey: DemoMaterial.p256Recipient, nonce: nil)]
    )

    static let unicodeSecret = #Obfuscated("Emoji: 🚀🔒", methods: [.xor(key: 0x2C), .base64])
    static let emptySecret = #Obfuscated("", methods: [.xor(key: 0x11)])
    static let interpolationSecret = #Obfuscated("Bearer \("demo-token")", methods: [.xor(key: 0x33), .base64])

    static let pipelineSecret = #Obfuscated(
        "Pipeline: xor -> shift -> base64",
        methods: [.xor(key: 0x2F), .bitShift(by: 2), .base64]
    )
    static let cryptoPipelineSecret = #Obfuscated(
        "Pipeline: xor -> AES -> base64",
        methods: [.xor(key: 0x11), .aesGCM(key: nil, nonce: nil), .base64]
    )
    static let hmacPipelineSecret = #Obfuscated(
        "Pipeline: HMAC -> base64",
        methods: [.hmacSHA256(key: nil, salt: nil), .base64]
    )
    static let hkdfPipelineSecret = #Obfuscated(
        "Pipeline: HKDF -> xor",
        methods: [.hkdfChaChaPoly(inputKey: nil, salt: nil, info: nil, nonce: nil), .xor(key: 0x55)]
    )

    static let rot13Secret = #Obfuscated(
        "Custom ROT13 protected secret",
        methods: [.custom(id: "rot13", parameters: ObfuscationParameters(bytes: [13]))]
    )
}

struct DemoExample: Identifiable {
    let id = UUID()
    let title: String
    let macroSource: String
    let plaintext: String
    let value: String
    let note: String?
    let encodedByteCount: Int
    let matchesPlaintextUTF8: Bool
}

enum DemoCatalog {
    private static func example(
        title: String,
        macroSource: String,
        plaintext: String,
        value: String,
        methods: [ObfuscationMethod],
        note: String? = nil
    ) -> DemoExample {
        let payload = try? ObfuscationPipeline.encode(plaintext, methods: methods)
        let plaintextBytes = Array(plaintext.utf8)
        return DemoExample(
            title: title,
            macroSource: macroSource,
            plaintext: plaintext,
            value: value,
            note: note,
            encodedByteCount: payload?.bytes.count ?? 0,
            matchesPlaintextUTF8: payload?.bytes == plaintextBytes
        )
    }

    static let methodExamples: [DemoExample] = [
        example(
            title: "XOR",
            macroSource: #"#Obfuscated("XOR protected secret", methods: [.xor(key: 0x5A)])"#,
            plaintext: "XOR protected secret",
            value: DemoSecrets.xorSecret,
            methods: [.xor(key: 0x5A)]
        ),
        example(
            title: "Bit Shift",
            macroSource: #"#Obfuscated("Bit-shift protected secret", methods: [.bitShift(by: 3)])"#,
            plaintext: "Bit-shift protected secret",
            value: DemoSecrets.shiftSecret,
            methods: [.bitShift(by: 3)]
        ),
        example(
            title: "Bit OR",
            macroSource: #"#Obfuscated("Bit-OR protected secret", methods: [.bitOr(mask: 0x80)])"#,
            plaintext: "Bit-OR protected secret",
            value: DemoSecrets.orSecret,
            methods: [.bitOr(mask: 0x80)],
            note: "Mask bits must be clear in the plaintext."
        ),
        example(
            title: "Base64",
            macroSource: #"#Obfuscated("Base64 protected secret", methods: [.base64])"#,
            plaintext: "Base64 protected secret",
            value: DemoSecrets.base64Secret,
            methods: [.base64]
        ),
        example(
            title: "AES-GCM",
            macroSource: #"#Obfuscated("AES protected secret", methods: [.aesGCM(key: nil, nonce: nil)])"#,
            plaintext: "AES protected secret",
            value: DemoSecrets.aesSecret,
            methods: [.aesGCM(key: nil, nonce: nil)],
            note: "nil key/nonce: generated at compile time and stored in CryptoMaterial."
        ),
        example(
            title: "ChaChaPoly",
            macroSource: #"#Obfuscated("ChaCha protected secret", methods: [.chaChaPoly(key: nil, nonce: nil)])"#,
            plaintext: "ChaCha protected secret",
            value: DemoSecrets.chachaSecret,
            methods: [.chaChaPoly(key: nil, nonce: nil)]
        ),
        example(
            title: "HMAC-SHA256",
            macroSource: #"#Obfuscated("HMAC protected secret", methods: [.hmacSHA256(key: nil, salt: nil)])"#,
            plaintext: "HMAC protected secret",
            value: DemoSecrets.hmacSecret,
            methods: [.hmacSHA256(key: nil, salt: nil)]
        ),
        example(
            title: "HMAC-SHA384",
            macroSource: #"#Obfuscated("HMAC-SHA384 protected secret", methods: [.hmacSHA384(key: nil, salt: nil)])"#,
            plaintext: "HMAC-SHA384 protected secret",
            value: DemoSecrets.hmac384Secret,
            methods: [.hmacSHA384(key: nil, salt: nil)]
        ),
        example(
            title: "HMAC-SHA512",
            macroSource: #"#Obfuscated("HMAC-SHA512 protected secret", methods: [.hmacSHA512(key: nil, salt: nil)])"#,
            plaintext: "HMAC-SHA512 protected secret",
            value: DemoSecrets.hmac512Secret,
            methods: [.hmacSHA512(key: nil, salt: nil)]
        ),
        example(
            title: "HKDF + AES-GCM",
            macroSource: #"#Obfuscated("HKDF protected secret", methods: [.hkdfAESGCM(inputKey: nil, salt: nil, info: nil, nonce: nil)])"#,
            plaintext: "HKDF protected secret",
            value: DemoSecrets.hkdfSecret,
            methods: [.hkdfAESGCM(inputKey: nil, salt: nil, info: nil, nonce: nil)]
        ),
        example(
            title: "HKDF + ChaChaPoly",
            macroSource: #"#Obfuscated("HKDF ChaCha protected secret", methods: [.hkdfChaChaPoly(inputKey: nil, salt: nil, info: nil, nonce: nil)])"#,
            plaintext: "HKDF ChaCha protected secret",
            value: DemoSecrets.hkdfChaChaSecret,
            methods: [.hkdfChaChaPoly(inputKey: nil, salt: nil, info: nil, nonce: nil)]
        ),
        example(
            title: "Curve25519 ECIES",
            macroSource: #"#Obfuscated("Curve25519 ECIES protected secret", methods: [.curve25519AESGCM(recipientPrivateKey: nil, nonce: nil)])"#,
            plaintext: "Curve25519 ECIES protected secret",
            value: DemoSecrets.curve25519Secret,
            methods: [.curve25519AESGCM(recipientPrivateKey: nil, nonce: nil)]
        ),
        example(
            title: "P256 ECIES",
            macroSource: #"#Obfuscated("P256 ECIES protected secret", methods: [.p256AESGCM(recipientPrivateKey: nil, nonce: nil)])"#,
            plaintext: "P256 ECIES protected secret",
            value: DemoSecrets.p256Secret,
            methods: [.p256AESGCM(recipientPrivateKey: nil, nonce: nil)]
        ),
    ]

    static let explicitMaterialExamples: [DemoExample] = [
        example(
            title: "AES-GCM (explicit key + nonce)",
            macroSource: """
            #Obfuscated(
                "AES with explicit key + nonce",
                methods: [.aesGCM(key: ObfuscatedKey(bytes: [0xAB, ...×16]),
                          nonce: ObfuscatedNonce(bytes: [0x10, ...×12]))]
            )
            """,
            plaintext: "AES with explicit key + nonce",
            value: DemoSecrets.explicitAESSecret,
            methods: [.aesGCM(key: DemoMaterial.aesKey, nonce: DemoMaterial.aesNonce)],
            note: "Fixed key material for reproducible compile-time output."
        ),
        example(
            title: "ChaChaPoly (explicit key + nonce)",
            macroSource: """
            #Obfuscated(
                "ChaCha with explicit key + nonce",
                methods: [.chaChaPoly(key: ObfuscatedKey(bytes: [0xCD, ...×32]),
                                      nonce: ObfuscatedNonce(bytes: [0x01, ...×12]))]
            )
            """,
            plaintext: "ChaCha with explicit key + nonce",
            value: DemoSecrets.explicitChaChaSecret,
            methods: [.chaChaPoly(key: DemoMaterial.chachaKey, nonce: DemoMaterial.chachaNonce)]
        ),
        example(
            title: "HMAC-SHA256 (explicit key + salt)",
            macroSource: """
            #Obfuscated(
                "HMAC with explicit key + salt",
                methods: [.hmacSHA256(key: ObfuscatedKey(bytes: [0x42, ...×32]),
                                      salt: ObfuscatedSalt(bytes: [0x73, 0x61, 0x6C, 0x74]))]
            )
            """,
            plaintext: "HMAC with explicit key + salt",
            value: DemoSecrets.explicitHMACSecret,
            methods: [.hmacSHA256(key: DemoMaterial.hmacKey, salt: DemoMaterial.hmacSalt)]
        ),
        example(
            title: "HKDF + AES-GCM (explicit material)",
            macroSource: """
            #Obfuscated(
                "HKDF with explicit input, salt, info, nonce",
                methods: [.hkdfAESGCM(
                    inputKey: ObfuscatedKey(bytes: [0x11, ...×32]),
                    salt: ObfuscatedSalt(bytes: [0xDE, 0xAD, 0xBE, 0xEF]),
                    info: ObfuscatedInfo(bytes: [0x4F, 0x62, ...]),
                    nonce: ObfuscatedNonce(bytes: [0x22, ...×12])
                )]
            )
            """,
            plaintext: "HKDF with explicit input, salt, info, nonce",
            value: DemoSecrets.explicitHKDFSecret,
            methods: [
                .hkdfAESGCM(
                    inputKey: DemoMaterial.hkdfInput,
                    salt: DemoMaterial.hkdfSalt,
                    info: DemoMaterial.hkdfInfo,
                    nonce: DemoMaterial.hkdfNonce
                ),
            ]
        ),
        example(
            title: "Curve25519 ECIES (explicit recipient key)",
            macroSource: """
            #Obfuscated(
                "Curve25519 with explicit recipient key",
                methods: [.curve25519AESGCM(
                    recipientPrivateKey: ObfuscatedKey(bytes: [128, 24, 244, ...]),
                    nonce: nil
                )]
            )
            """,
            plaintext: "Curve25519 with explicit recipient key",
            value: DemoSecrets.explicitCurve25519Secret,
            methods: [.curve25519AESGCM(recipientPrivateKey: DemoMaterial.curve25519Recipient, nonce: nil)]
        ),
        example(
            title: "P256 ECIES (explicit recipient key)",
            macroSource: """
            #Obfuscated(
                "P256 with explicit recipient key",
                methods: [.p256AESGCM(
                    recipientPrivateKey: ObfuscatedKey(bytes: [133, 243, 49, ...]),
                    nonce: nil
                )]
            )
            """,
            plaintext: "P256 with explicit recipient key",
            value: DemoSecrets.explicitP256Secret,
            methods: [.p256AESGCM(recipientPrivateKey: DemoMaterial.p256Recipient, nonce: nil)]
        ),
    ]

    static let customStepExamples: [DemoExample] = [
        example(
            title: "Custom ROT13",
            macroSource: #"#Obfuscated("Custom ROT13 protected secret", methods: [.custom(id: "rot13", parameters: ObfuscationParameters(bytes: [13]))])"#,
            plaintext: "Custom ROT13 protected secret",
            value: DemoSecrets.rot13Secret,
            methods: [.custom(id: "rot13", parameters: ObfuscationParameters(bytes: [13]))],
            note: "User-defined ObfuscationStep registered in the demo macro plugin."
        ),
    ]

    static let edgeCaseExamples: [DemoExample] = [
        example(
            title: "Unicode + Emoji",
            macroSource: #"#Obfuscated("Emoji: 🚀🔒", methods: [.xor(key: 0x2C), .base64])"#,
            plaintext: "Emoji: 🚀🔒",
            value: DemoSecrets.unicodeSecret,
            methods: [.xor(key: 0x2C), .base64],
            note: "Non-ASCII payloads round-trip through the pipeline."
        ),
        example(
            title: "Empty String",
            macroSource: #"#Obfuscated("", methods: [.xor(key: 0x11)])"#,
            plaintext: "",
            value: DemoSecrets.emptySecret,
            methods: [.xor(key: 0x11)],
            note: "Zero-length literals are valid."
        ),
        example(
            title: "Static Interpolation",
            macroSource: #"#Obfuscated("Bearer \("demo-token")", methods: [.xor(key: 0x33), .base64])"#,
            plaintext: "Bearer demo-token",
            value: DemoSecrets.interpolationSecret,
            methods: [.xor(key: 0x33), .base64],
            note: #"\("...") segments must be string literals; folded to one string at compile time."#
        ),
    ]

    static let pipelineExamples: [DemoExample] = [
        example(
            title: "XOR + Shift + Base64",
            macroSource: """
            #Obfuscated(
                "Pipeline: xor -> shift -> base64",
                methods: [.xor(key: 0x2F), .bitShift(by: 2), .base64]
            )
            """,
            plaintext: "Pipeline: xor -> shift -> base64",
            value: DemoSecrets.pipelineSecret,
            methods: [.xor(key: 0x2F), .bitShift(by: 2), .base64]
        ),
        example(
            title: "XOR + AES + Base64",
            macroSource: """
            #Obfuscated(
                "Pipeline: xor -> AES -> base64",
                methods: [.xor(key: 0x11), .aesGCM(key: nil, nonce: nil), .base64]
            )
            """,
            plaintext: "Pipeline: xor -> AES -> base64",
            value: DemoSecrets.cryptoPipelineSecret,
            methods: [.xor(key: 0x11), .aesGCM(key: nil, nonce: nil), .base64]
        ),
        example(
            title: "HMAC + Base64",
            macroSource: """
            #Obfuscated(
                "Pipeline: HMAC -> base64",
                methods: [.hmacSHA256(key: nil, salt: nil), .base64]
            )
            """,
            plaintext: "Pipeline: HMAC -> base64",
            value: DemoSecrets.hmacPipelineSecret,
            methods: [.hmacSHA256(key: nil, salt: nil), .base64]
        ),
        example(
            title: "HKDF + XOR",
            macroSource: """
            #Obfuscated(
                "Pipeline: HKDF -> xor",
                methods: [.hkdfChaChaPoly(inputKey: nil, salt: nil, info: nil, nonce: nil), .xor(key: 0x55)]
            )
            """,
            plaintext: "Pipeline: HKDF -> xor",
            value: DemoSecrets.hkdfPipelineSecret,
            methods: [.hkdfChaChaPoly(inputKey: nil, salt: nil, info: nil, nonce: nil), .xor(key: 0x55)]
        ),
    ]
}
