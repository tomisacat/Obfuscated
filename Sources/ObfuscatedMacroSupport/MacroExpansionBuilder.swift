import ObfuscatedCore
import SwiftSyntax
import SwiftSyntaxBuilder

/// Builds Swift source for macro expansions that call ``ObfuscatedRuntime/_decode(bytes:methods:material:)``.
public enum MacroExpansionBuilder {
    /// Encodes a string at compile time and builds the decode call expression.
    public static func decodeExpression(string: String, methods: [ObfuscationMethod]) throws -> ExprSyntax {
        ObfuscationMacroConfiguration.ensureRegistered()
        let payload = try ObfuscationPipeline.encode(string, methods: methods)
        return try decodeExpression(payload: payload, methods: methods)
    }

    /// Builds the decode call expression from a pre-encoded payload.
    public static func decodeExpression(payload: EncodedPayload, methods: [ObfuscationMethod]) throws -> ExprSyntax {
        let bytesLiteral = payload.bytes.map(String.init).joined(separator: ", ")
        let methodsLiteral = try methodsSyntax(methods)
        let materialLiteral = materialSyntax(payload.material)

        return """
        ObfuscatedRuntime._decode(
            bytes: [\(raw: bytesLiteral)],
            methods: \(methodsLiteral),
            material: \(raw: materialLiteral)
        )
        """
    }

    private static func methodsSyntax(_ methods: [ObfuscationMethod]) throws -> ExprSyntax {
        let rendered = try methods.map { try methodSyntax($0) }.joined(separator: ", ")
        return "[\(raw: rendered)]"
    }

    private static func methodSyntax(_ method: ObfuscationMethod) throws -> String {
        switch method {
        case .xor(let key):
            return ".xor(key: \(key))"
        case .bitShift(let amount):
            return ".bitShift(by: \(amount))"
        case .bitOr(let mask):
            return ".bitOr(mask: \(mask))"
        case .base64:
            return ".base64"
        case .custom(let id, let parameters):
            return ".custom(id: \"\(id)\", parameters: \(parametersSyntax(parameters)))"
        case .aesGCM(let key, let nonce):
            return ".aesGCM(key: \(optionalKeySyntax(key)), nonce: \(optionalNonceSyntax(nonce)))"
        case .chaChaPoly(let key, let nonce):
            return ".chaChaPoly(key: \(optionalKeySyntax(key)), nonce: \(optionalNonceSyntax(nonce)))"
        case .chacha20(let key, let nonce):
            return ".chacha20(key: \(optionalKeySyntax(key)), nonce: \(optionalNonceSyntax(nonce)))"
        case .hmacSHA256(let key, let salt):
            return ".hmacSHA256(key: \(optionalKeySyntax(key)), salt: \(optionalSaltSyntax(salt)))"
        case .hmacSHA384(let key, let salt):
            return ".hmacSHA384(key: \(optionalKeySyntax(key)), salt: \(optionalSaltSyntax(salt)))"
        case .hmacSHA512(let key, let salt):
            return ".hmacSHA512(key: \(optionalKeySyntax(key)), salt: \(optionalSaltSyntax(salt)))"
        case .hkdfAESGCM(let inputKey, let salt, let info, let nonce):
            return ".hkdfAESGCM(inputKey: \(optionalKeySyntax(inputKey)), salt: \(optionalSaltSyntax(salt)), info: \(optionalInfoSyntax(info)), nonce: \(optionalNonceSyntax(nonce)))"
        case .hkdfChaChaPoly(let inputKey, let salt, let info, let nonce):
            return ".hkdfChaChaPoly(inputKey: \(optionalKeySyntax(inputKey)), salt: \(optionalSaltSyntax(salt)), info: \(optionalInfoSyntax(info)), nonce: \(optionalNonceSyntax(nonce)))"
        case .curve25519AESGCM(let privateKey, let nonce):
            return ".curve25519AESGCM(recipientPrivateKey: \(optionalKeySyntax(privateKey)), nonce: \(optionalNonceSyntax(nonce)))"
        case .p256AESGCM(let privateKey, let nonce):
            return ".p256AESGCM(recipientPrivateKey: \(optionalKeySyntax(privateKey)), nonce: \(optionalNonceSyntax(nonce)))"
        }
    }

    private static func parametersSyntax(_ parameters: ObfuscationParameters) -> String {
        "ObfuscationParameters(bytes: \(byteArrayLiteral(parameters.bytes)))"
    }

    private static func optionalKeySyntax(_ key: ObfuscatedKey?) -> String {
        guard let key else { return "nil" }
        return "ObfuscatedKey(bytes: \(byteArrayLiteral(key.bytes)))"
    }

    private static func optionalNonceSyntax(_ nonce: ObfuscatedNonce?) -> String {
        guard let nonce else { return "nil" }
        return "ObfuscatedNonce(bytes: \(byteArrayLiteral(nonce.bytes)))"
    }

    private static func optionalSaltSyntax(_ salt: ObfuscatedSalt?) -> String {
        guard let salt else { return "nil" }
        return "ObfuscatedSalt(bytes: \(byteArrayLiteral(salt.bytes)))"
    }

    private static func optionalInfoSyntax(_ info: ObfuscatedInfo?) -> String {
        guard let info else { return "nil" }
        return "ObfuscatedInfo(bytes: \(byteArrayLiteral(info.bytes)))"
    }

    private static func materialSyntax(_ material: CryptoMaterial) -> String {
        if material.entries.isEmpty && material.customEntries.isEmpty {
            return "CryptoMaterial(entries: [])"
        }

        let entries = material.entries.map(cryptoEntrySyntax).joined(separator: ", ")
        let customEntries = material.customEntries.map(customEntrySyntax).joined(separator: ", ")

        if material.customEntries.isEmpty {
            return """
            CryptoMaterial(
                entries: [\(entries)]
            )
            """
        }

        if material.entries.isEmpty {
            return """
            CryptoMaterial(
                entries: [],
                customEntries: [\(customEntries)]
            )
            """
        }

        return """
        CryptoMaterial(
            entries: [\(entries)],
            customEntries: [\(customEntries)]
        )
        """
    }

    private static func cryptoEntrySyntax(_ entry: CryptoEntry) -> String {
        """
        CryptoEntry(
            algorithm: .\(entry.algorithm.rawValue),
            payload: \(byteArrayLiteral(entry.payload)),
            primary: \(byteArrayLiteral(entry.primary)),
            secondary: \(byteArrayLiteral(entry.secondary)),
            tertiary: \(byteArrayLiteral(entry.tertiary)),
            primaryMask: \(entry.primaryMask),
            secondaryMask: \(entry.secondaryMask),
            tertiaryMask: \(entry.tertiaryMask)
        )
        """
    }

    private static func customEntrySyntax(_ entry: CustomMaterialEntry) -> String {
        """
        CustomMaterialEntry(
            id: "\(entry.id)",
            payload: \(byteArrayLiteral(entry.payload))
        )
        """
    }

    private static func byteArrayLiteral(_ bytes: [UInt8]) -> String {
        "[\(bytes.map(String.init).joined(separator: ", "))]"
    }
}
