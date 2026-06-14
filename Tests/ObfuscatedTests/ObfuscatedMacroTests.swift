@testable import ObfuscatedCore
import ObfuscatedMacroSupport
import ObfuscatedTestSupport
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

private let testMacros: [String: Macro.Type] = [
    "Obfuscated": ObfuscatedMacro.self,
]

private func withDeterministicRandom(_ body: () throws -> Void) rethrows {
    SecureRandom.useDeterministicValuesForTesting = true
    defer { SecureRandom.useDeterministicValuesForTesting = false }
    try body()
}

private func withRegisteredCustomSteps(_ body: () throws -> Void) rethrows {
    ObfuscationStepRegistry.reset()
    ObfuscationStepRegistry.register(MyRot13Step.self)
    ObfuscationMacroConfiguration.configure {
        ObfuscationStepRegistry.register(MyRot13Step.self)
    }
    defer { ObfuscationStepRegistry.reset() }
    try body()
}

private func assertCryptoMacro(
    string: String,
    methodSyntax: String,
    methods: [ObfuscationMethod]
) throws {
    try withDeterministicRandom {
        let parsed = try MacroSyntaxParser.parseMethods(from: ExprSyntax(stringLiteral: "[\(methodSyntax)]"))
        #expect(parsed == methods)

        let payload = try ObfuscationPipeline.encode(string, methods: methods)
        #expect(try ObfuscationPipeline.decode(payload, methods: methods) == string)

        let expansion = try MacroExpansionBuilder.decodeExpression(string: string, methods: methods)
        #expect(expansion.description.contains("ObfuscatedRuntime._decode"))
        #expect(expansion.description.contains("CryptoMaterial"))
    }
}

@Suite("Obfuscated macros")
struct ObfuscatedMacroTests {
    @Test func xorMacroExpansion() throws {
        let methods: [ObfuscationMethod] = [.xor(key: 90)]
        let expanded = try MacroExpansionBuilder.decodeExpression(string: "Secret", methods: methods)

        assertMacroExpansion(
            """
            #Obfuscated("Secret", methods: [.xor(key: 90)])
            """,
            expandedSource: expanded.description,
            macros: testMacros
        )
    }

    @Test func pipelineMacroExpansion() throws {
        let methods: [ObfuscationMethod] = [.xor(key: 10), .base64]
        let expanded = try MacroExpansionBuilder.decodeExpression(string: "Chain", methods: methods)

        assertMacroExpansion(
            """
            #Obfuscated("Chain", methods: [.xor(key: 10), .base64])
            """,
            expandedSource: expanded.description,
            macros: testMacros
        )
    }

    @Test func staticInterpolationMacroExpansion() throws {
        let methods: [ObfuscationMethod] = [.xor(key: 90)]
        let expanded = try MacroExpansionBuilder.decodeExpression(string: "Bearer abc", methods: methods)

        assertMacroExpansion(
            """
            #Obfuscated("Bearer \\("abc")", methods: [.xor(key: 90)])
            """,
            expandedSource: expanded.description,
            macros: testMacros
        )
    }

    @Test func staticInterpolationFoldsNestedLiterals() throws {
        let methods: [ObfuscationMethod] = [.xor(key: 10)]
        let expanded = try MacroExpansionBuilder.decodeExpression(string: "pre-value-post", methods: methods)

        assertMacroExpansion(
            """
            #Obfuscated("pre-\\("val\\("ue")")-post", methods: [.xor(key: 10)])
            """,
            expandedSource: expanded.description,
            macros: testMacros
        )
    }

    @Test func staticInterpolationRoundTrip() throws {
        let methods: [ObfuscationMethod] = [.xor(key: 0x5A), .base64]
        let folded = "Bearer my-token"
        let payload = try ObfuscationPipeline.encode(folded, methods: methods)
        #expect(try ObfuscationPipeline.decode(payload, methods: methods) == folded)
    }

    @Test func xorMacroExpansionWithHexLiteral() throws {
        let methods: [ObfuscationMethod] = [.xor(key: 0x5A)]
        let expanded = try MacroExpansionBuilder.decodeExpression(string: "Secret", methods: methods)

        assertMacroExpansion(
            """
            #Obfuscated("Secret", methods: [.xor(key: 0x5A)])
            """,
            expandedSource: expanded.description,
            macros: testMacros
        )
    }

    @Test func aesGCMMacroExpansion() throws {
        try assertCryptoMacro(
            string: "AES secret",
            methodSyntax: ".aesGCM(key: nil, nonce: nil)",
            methods: [.aesGCM(key: nil, nonce: nil)]
        )
    }

    @Test func chaChaPolyMacroExpansion() throws {
        try assertCryptoMacro(
            string: "ChaCha secret",
            methodSyntax: ".chaChaPoly(key: nil, nonce: nil)",
            methods: [.chaChaPoly(key: nil, nonce: nil)]
        )
    }

    @Test func hmacSHA256MacroExpansion() throws {
        try assertCryptoMacro(
            string: "HMAC secret",
            methodSyntax: ".hmacSHA256(key: nil, salt: nil)",
            methods: [.hmacSHA256(key: nil, salt: nil)]
        )
    }

    @Test func hmacSHA384MacroExpansion() throws {
        try assertCryptoMacro(
            string: "HMAC384 secret",
            methodSyntax: ".hmacSHA384(key: nil, salt: nil)",
            methods: [.hmacSHA384(key: nil, salt: nil)]
        )
    }

    @Test func hmacSHA512MacroExpansion() throws {
        try assertCryptoMacro(
            string: "HMAC512 secret",
            methodSyntax: ".hmacSHA512(key: nil, salt: nil)",
            methods: [.hmacSHA512(key: nil, salt: nil)]
        )
    }

    @Test func hkdfAESGCMMacroExpansion() throws {
        try assertCryptoMacro(
            string: "HKDF secret",
            methodSyntax: ".hkdfAESGCM(inputKey: nil, salt: nil, info: nil, nonce: nil)",
            methods: [.hkdfAESGCM(inputKey: nil, salt: nil, info: nil, nonce: nil)]
        )
    }

    @Test func hkdfChaChaPolyMacroExpansion() throws {
        try assertCryptoMacro(
            string: "HKDF ChaCha secret",
            methodSyntax: ".hkdfChaChaPoly(inputKey: nil, salt: nil, info: nil, nonce: nil)",
            methods: [.hkdfChaChaPoly(inputKey: nil, salt: nil, info: nil, nonce: nil)]
        )
    }

    @Test func curve25519AESGCMMacroExpansion() throws {
        try assertCryptoMacro(
            string: "Curve25519 secret",
            methodSyntax: ".curve25519AESGCM(recipientPrivateKey: nil, nonce: nil)",
            methods: [.curve25519AESGCM(recipientPrivateKey: nil, nonce: nil)]
        )
    }

    @Test func p256AESGCMMacroExpansion() throws {
        try assertCryptoMacro(
            string: "P256 secret",
            methodSyntax: ".p256AESGCM(recipientPrivateKey: nil, nonce: nil)",
            methods: [.p256AESGCM(recipientPrivateKey: nil, nonce: nil)]
        )
    }

    @Test func encodedBytesDoNotMatchPlaintext() throws {
        let payload = try ObfuscationPipeline.encode("PlaintextValue", methods: [.xor(key: 1)])
        #expect(payload.bytes != Array("PlaintextValue".utf8))
    }

    @Test func customStepMacroExpansion() throws {
        try withRegisteredCustomSteps {
            let methods: [ObfuscationMethod] = [
                .custom(id: MyRot13Step.id, parameters: ObfuscationParameters(bytes: [13])),
            ]
            let expanded = try MacroExpansionBuilder.decodeExpression(string: "Custom secret", methods: methods)
            #expect(expanded.description.contains("ObfuscatedRuntime._decode"))
            #expect(expanded.description.contains("rot13"))
            #expect(expanded.description.contains("ObfuscationParameters"))
            #expect(expanded.description.contains("CryptoMaterial(entries: [])"))
        }
    }

    @Test func customStepMacroRoundTrip() throws {
        try withRegisteredCustomSteps {
            let methods: [ObfuscationMethod] = [
                .custom(id: MyRot13Step.id, parameters: ObfuscationParameters(bytes: [13])),
            ]
            let payload = try ObfuscationPipeline.encode("Macro custom", methods: methods)
            #expect(try ObfuscationPipeline.decode(payload, methods: methods) == "Macro custom")
        }
    }

    @Test func intMacroExpansion() throws {
        let methods: [ObfuscationMethod] = [.xor(key: 0x5A)]
        let expanded = try MacroExpansionBuilder.decodeExpression(value: 443, methods: methods, as: Int.self)

        assertMacroExpansion(
            """
            #Obfuscated(443, methods: [.xor(key: 0x5A)])
            """,
            expandedSource: expanded.description,
            macros: testMacros
        )
        #expect(expanded.description.contains("as: Int.self"))
    }

    @Test func boolMacroExpansion() throws {
        let methods: [ObfuscationMethod] = [.xor(key: 1)]
        let expanded = try MacroExpansionBuilder.decodeExpression(value: true, methods: methods, as: Bool.self)
        #expect(expanded.description.contains("as: Bool.self"))
    }

    @Test func dataMacroExpansion() throws {
        let methods: [ObfuscationMethod] = [.xor(key: 0x33)]
        let expanded = try MacroExpansionBuilder.decodeDataExpression(bytes: [0x01, 0x02], methods: methods)
        #expect(expanded.description.contains("as: Data.self"))
    }

    @Test func enumCaseMacroExpansion() throws {
        let methods: [ObfuscationMethod] = [.xor(key: 0x11)]
        let expanded = try MacroExpansionBuilder.decodeEnumCaseExpression(
            caseName: "production",
            typeName: "Environment",
            methods: methods
        )
        #expect(expanded.description.contains("_decodeCaseIterable"))
        #expect(expanded.description.contains("caseName: \"production\""))
        #expect(expanded.description.contains("as: Environment.self"))
    }

    @Test func rawRepresentableIntMacroExpansion() throws {
        let methods: [ObfuscationMethod] = [.xor(key: 0x09)]
        let expanded = try MacroExpansionBuilder.decodeRawRepresentableExpression(
            rawValue: 1,
            typeName: "Color.self",
            methods: methods
        )
        #expect(expanded.description.contains("_decodeRawRepresentable"))
        #expect(expanded.description.contains("as: Color.self"))
    }
}
