import ObfuscatedCore
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Parses macro argument syntax into runtime values used by the expansion builder.
enum MacroSyntaxParser {
    /// Folds a string literal into a single static value, including `\("...")` segments.
    ///
    /// Every `\(...)` expression must itself be a foldable static string literal.
    /// Runtime variables inside interpolations are rejected.
    ///
    /// - Parameter expression: Macro argument expression syntax.
    /// - Returns: The combined plaintext, or `nil` when folding fails.
    static func foldedStaticString(from expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self) else {
            return nil
        }

        var result = ""
        for segment in literal.segments {
            switch segment {
            case .stringSegment(let stringSegment):
                result += String(stringSegment.content.text)
            case .expressionSegment(let expressionSegment):
                guard let interpolated = expressionSegment.expressions.first?.expression,
                      let folded = foldedStaticString(from: ExprSyntax(interpolated))
                else {
                    return nil
                }
                result += folded
            }
        }

        return result
    }

    /// Extracts a static string literal from a syntax expression.
    ///
    /// Supports plain literals and literals whose `\(...)` segments are also static strings.
    ///
    /// - Parameter expression: Macro argument expression syntax.
    /// - Returns: The folded plaintext, or `nil` when the expression is not a static string literal.
    static func stringLiteral(from expression: ExprSyntax) -> String? {
        foldedStaticString(from: expression)
    }

    /// Parses integer literal text supporting decimal, hex, octal, and binary prefixes.
    ///
    /// - Parameter text: Raw integer literal text from source.
    /// - Returns: The parsed integer, or `nil` when the text is invalid.
    static func parseIntegerLiteral(_ text: String) -> Int? {
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            return Int(text.dropFirst(2), radix: 16)
        }
        if text.hasPrefix("0o") || text.hasPrefix("0O") {
            return Int(text.dropFirst(2), radix: 8)
        }
        if text.hasPrefix("0b") || text.hasPrefix("0B") {
            return Int(text.dropFirst(2), radix: 2)
        }
        return Int(text)
    }

    /// Parses a `UInt8` integer literal expression.
    ///
    /// - Parameter expression: Macro argument expression syntax.
    /// - Returns: A byte value in `0…255`, or `nil` when out of range or not an integer literal.
    static func uint8(from expression: ExprSyntax) -> UInt8? {
        guard let text = expression.as(IntegerLiteralExprSyntax.self)?.literal.text,
              let value = parseIntegerLiteral(text),
              (0 ... 255).contains(value)
        else {
            return nil
        }
        return UInt8(value)
    }

    /// Parses a signed integer literal expression.
    ///
    /// - Parameter expression: Macro argument expression syntax.
    /// - Returns: The parsed `Int`, or `nil` when the expression is not an integer literal.
    static func int(from expression: ExprSyntax) -> Int? {
        guard let text = expression.as(IntegerLiteralExprSyntax.self)?.literal.text else {
            return nil
        }
        return parseIntegerLiteral(text)
    }

    /// Parses an array literal of `UInt8` integer literals.
    ///
    /// - Parameter expression: Optional array expression syntax.
    /// - Returns: Parsed byte values, or `nil` when any element is not a valid byte literal.
    static func byteArray(from expression: ExprSyntax?) -> [UInt8]? {
        guard let expression,
              let array = expression.as(ArrayExprSyntax.self)
        else {
            return nil
        }

        var bytes: [UInt8] = []
        for element in array.elements {
            guard let value = uint8(from: element.expression) else {
                return nil
            }
            bytes.append(value)
        }
        return bytes
    }

    /// Parses a `methods:` array literal into ``ObfuscationMethod`` values.
    ///
    /// - Parameter expression: The `methods` macro argument expression.
    /// - Returns: Ordered obfuscation methods.
    /// - Throws: ``ObfuscatedMacroError`` when the expression is not a supported array literal.
    static func parseMethods(from expression: ExprSyntax) throws -> [ObfuscationMethod] {
        guard let array = expression.as(ArrayExprSyntax.self) else {
            throw ObfuscatedMacroError.invalidMethodsExpression
        }

        var methods: [ObfuscationMethod] = []
        for element in array.elements {
            methods.append(try parseMethod(from: element.expression))
        }
        return methods
    }

    /// Parses one obfuscation method call or enum case from macro syntax.
    ///
    /// - Parameter expression: A method element from the `methods` array.
    /// - Returns: The corresponding ``ObfuscationMethod`` value.
    /// - Throws: ``ObfuscatedMacroError`` for unsupported or malformed method syntax.
    static func parseMethod(from expression: ExprSyntax) throws -> ObfuscationMethod {
        if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
            switch memberAccess.declName.baseName.text {
            case "base64":
                return .base64
            default:
                throw ObfuscatedMacroError.unsupportedMethod(expression.description)
            }
        }

        guard let function = expression.as(FunctionCallExprSyntax.self) else {
            throw ObfuscatedMacroError.unsupportedMethod(expression.description)
        }

        let name: String
        if let reference = function.calledExpression.as(DeclReferenceExprSyntax.self) {
            name = reference.baseName.text
        } else if let memberAccess = function.calledExpression.as(MemberAccessExprSyntax.self) {
            name = memberAccess.declName.baseName.text
        } else {
            throw ObfuscatedMacroError.unsupportedMethod(expression.description)
        }

        let arguments = labeledArguments(in: function.arguments)

        switch name {
        case "xor":
            guard let keyExpr = arguments["key"], let key = uint8(from: keyExpr) else {
                throw ObfuscatedMacroError.missingArgument("key", for: name)
            }
            return .xor(key: key)
        case "bitShift":
            guard let byExpr = arguments["by"], let amount = int(from: byExpr) else {
                throw ObfuscatedMacroError.missingArgument("by", for: name)
            }
            return .bitShift(by: amount)
        case "bitOr":
            guard let maskExpr = arguments["mask"], let mask = uint8(from: maskExpr) else {
                throw ObfuscatedMacroError.missingArgument("mask", for: name)
            }
            return .bitOr(mask: mask)
        case "base64":
            return .base64
        case "aesGCM":
            return .aesGCM(
                key: obfuscatedKey(from: arguments["key"]),
                nonce: obfuscatedNonce(from: arguments["nonce"])
            )
        case "chaChaPoly", "chacha20":
            return .chaChaPoly(
                key: obfuscatedKey(from: arguments["key"]),
                nonce: obfuscatedNonce(from: arguments["nonce"])
            )
        case "hmacSHA256":
            return .hmacSHA256(
                key: obfuscatedKey(from: arguments["key"]),
                salt: obfuscatedSalt(from: arguments["salt"])
            )
        case "hmacSHA384":
            return .hmacSHA384(
                key: obfuscatedKey(from: arguments["key"]),
                salt: obfuscatedSalt(from: arguments["salt"])
            )
        case "hmacSHA512":
            return .hmacSHA512(
                key: obfuscatedKey(from: arguments["key"]),
                salt: obfuscatedSalt(from: arguments["salt"])
            )
        case "hkdfAESGCM":
            return .hkdfAESGCM(
                inputKey: obfuscatedKey(from: arguments["inputKey"]),
                salt: obfuscatedSalt(from: arguments["salt"]),
                info: obfuscatedInfo(from: arguments["info"]),
                nonce: obfuscatedNonce(from: arguments["nonce"])
            )
        case "hkdfChaChaPoly":
            return .hkdfChaChaPoly(
                inputKey: obfuscatedKey(from: arguments["inputKey"]),
                salt: obfuscatedSalt(from: arguments["salt"]),
                info: obfuscatedInfo(from: arguments["info"]),
                nonce: obfuscatedNonce(from: arguments["nonce"])
            )
        case "curve25519AESGCM":
            return .curve25519AESGCM(
                recipientPrivateKey: obfuscatedKey(from: arguments["recipientPrivateKey"]),
                nonce: obfuscatedNonce(from: arguments["nonce"])
            )
        case "p256AESGCM":
            return .p256AESGCM(
                recipientPrivateKey: obfuscatedKey(from: arguments["recipientPrivateKey"]),
                nonce: obfuscatedNonce(from: arguments["nonce"])
            )
        default:
            throw ObfuscatedMacroError.unsupportedMethod(name)
        }
    }

    /// Parses an optional ``ObfuscatedSalt`` initializer call from macro syntax.
    private static func obfuscatedSalt(from expression: ExprSyntax?) -> ObfuscatedSalt? {
        obfuscatedBytesType(from: expression, typeName: "ObfuscatedSalt").map(ObfuscatedSalt.init)
    }

    /// Parses an optional ``ObfuscatedInfo`` initializer call from macro syntax.
    private static func obfuscatedInfo(from expression: ExprSyntax?) -> ObfuscatedInfo? {
        obfuscatedBytesType(from: expression, typeName: "ObfuscatedInfo").map(ObfuscatedInfo.init)
    }

    /// Parses `nil` or a `TypeName(bytes: [...])` initializer into raw bytes.
    private static func obfuscatedBytesType(from expression: ExprSyntax?, typeName: String) -> [UInt8]? {
        guard let expression else { return nil }
        if expression.is(NilLiteralExprSyntax.self) { return nil }
        if let function = expression.as(FunctionCallExprSyntax.self),
           function.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == typeName,
           let bytesExpr = labeledArguments(in: function.arguments)["bytes"],
           let bytes = byteArray(from: bytesExpr)
        {
            return bytes
        }
        return nil
    }

    /// Collects labeled macro call arguments into a dictionary keyed by label text.
    private static func labeledArguments(in arguments: LabeledExprListSyntax) -> [String: ExprSyntax] {
        var result: [String: ExprSyntax] = [:]
        for argument in arguments {
            if let label = argument.label?.text {
                result[label] = argument.expression
            }
        }
        return result
    }

    /// Parses an optional ``ObfuscatedKey`` initializer call from macro syntax.
    private static func obfuscatedKey(from expression: ExprSyntax?) -> ObfuscatedKey? {
        guard let expression else { return nil }

        if expression.is(NilLiteralExprSyntax.self) {
            return nil
        }

        if let function = expression.as(FunctionCallExprSyntax.self),
           function.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "ObfuscatedKey",
           let bytesExpr = labeledArguments(in: function.arguments)["bytes"],
           let bytes = byteArray(from: bytesExpr)
        {
            return ObfuscatedKey(bytes: bytes)
        }

        return nil
    }

    /// Parses an optional ``ObfuscatedNonce`` initializer call from macro syntax.
    private static func obfuscatedNonce(from expression: ExprSyntax?) -> ObfuscatedNonce? {
        guard let expression else { return nil }

        if expression.is(NilLiteralExprSyntax.self) {
            return nil
        }

        if let function = expression.as(FunctionCallExprSyntax.self),
           function.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "ObfuscatedNonce",
           let bytesExpr = labeledArguments(in: function.arguments)["bytes"],
           let bytes = byteArray(from: bytesExpr)
        {
            return ObfuscatedNonce(bytes: bytes)
        }

        return nil
    }
}

/// Errors surfaced during macro argument parsing and compile-time encoding.
enum ObfuscatedMacroError: Error, CustomStringConvertible {
    /// The macro was not given a string literal as its payload.
    case missingStringLiteral
    /// A `\(...)` segment is not a static string literal.
    case nonStaticStringInterpolation
    /// The macro call is missing a `methods:` argument.
    case missingMethodsArgument
    /// The `methods:` argument is not an array literal of supported method calls.
    case invalidMethodsExpression
    /// A method name or syntax shape is not supported by the parser.
    case unsupportedMethod(String)
    /// A required labeled argument is missing from a method call.
    case missingArgument(String, for: String)
    /// ``ObfuscationPipeline/encode(_:methods:)`` failed while expanding the macro.
    case encodingFailed(String)

    /// Human-readable diagnostic text shown at the macro use site.
    var description: String {
        switch self {
        case .missingStringLiteral:
            "#Obfuscated requires a string literal (variables are not supported)"
        case .nonStaticStringInterpolation:
            "#Obfuscated interpolation must be a string literal, e.g. \"Bearer \\(\"token\")\""
        case .missingMethodsArgument:
            "#Obfuscated requires a `methods:` argument"
        case .invalidMethodsExpression:
            "`methods:` must be an array literal of obfuscation methods"
        case .unsupportedMethod(let method):
            "Unsupported obfuscation method: \(method)"
        case .missingArgument(let argument, let method):
            "Missing `\(argument)` argument for `\(method)`"
        case .encodingFailed(let message):
            "Failed to obfuscate string: \(message)"
        }
    }
}

/// Builds Swift source for macro expansions that call ``ObfuscatedRuntime/_decode(bytes:methods:material:)``.
enum MacroExpansionBuilder {
    /// Encodes a string at compile time and builds the decode call expression.
    ///
    /// - Parameters:
    ///   - string: Plaintext string literal to obfuscate.
    ///   - methods: Parsed obfuscation pipeline.
    /// - Returns: Syntax for an `ObfuscatedRuntime._decode(...)` expression.
    /// - Throws: ``ObfuscatedMacroError/encodingFailed(_:)`` or pipeline errors.
    static func decodeExpression(string: String, methods: [ObfuscationMethod]) throws -> ExprSyntax {
        let payload = try ObfuscationPipeline.encode(string, methods: methods)
        return try decodeExpression(payload: payload, methods: methods)
    }

    /// Builds the decode call expression from a pre-encoded payload.
    ///
    /// - Parameters:
    ///   - payload: Compile-time encoded bytes and crypto material.
    ///   - methods: Method descriptors embedded into the expansion.
    /// - Returns: Syntax for an `ObfuscatedRuntime._decode(...)` expression.
    static func decodeExpression(payload: EncodedPayload, methods: [ObfuscationMethod]) throws -> ExprSyntax {
        let bytesLiteral = payload.bytes.map(String.init).joined(separator: ", ")
        let methodsLiteral = try methodsSyntax(methods)
        let materialLiteral = try materialSyntax(payload.material)

        return """
        ObfuscatedRuntime._decode(
            bytes: [\(raw: bytesLiteral)],
            methods: \(methodsLiteral),
            material: \(materialLiteral)
        )
        """
    }

    /// Renders an array literal of ``ObfuscationMethod`` cases for the expansion.
    private static func methodsSyntax(_ methods: [ObfuscationMethod]) throws -> ExprSyntax {
        let rendered = try methods.map { try methodSyntax($0) }.joined(separator: ", ")
        return "[\(raw: rendered)]"
    }

    /// Renders one ``ObfuscationMethod`` case as Swift source text.
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

    /// Renders an optional ``ObfuscatedKey`` as `nil` or an initializer call.
    private static func optionalKeySyntax(_ key: ObfuscatedKey?) -> String {
        guard let key else { return "nil" }
        return "ObfuscatedKey(bytes: \(byteArrayLiteral(key.bytes)))"
    }

    /// Renders an optional ``ObfuscatedNonce`` as `nil` or an initializer call.
    private static func optionalNonceSyntax(_ nonce: ObfuscatedNonce?) -> String {
        guard let nonce else { return "nil" }
        return "ObfuscatedNonce(bytes: \(byteArrayLiteral(nonce.bytes)))"
    }

    /// Renders an optional ``ObfuscatedSalt`` as `nil` or an initializer call.
    private static func optionalSaltSyntax(_ salt: ObfuscatedSalt?) -> String {
        guard let salt else { return "nil" }
        return "ObfuscatedSalt(bytes: \(byteArrayLiteral(salt.bytes)))"
    }

    /// Renders an optional ``ObfuscatedInfo`` as `nil` or an initializer call.
    private static func optionalInfoSyntax(_ info: ObfuscatedInfo?) -> String {
        guard let info else { return "nil" }
        return "ObfuscatedInfo(bytes: \(byteArrayLiteral(info.bytes)))"
    }

    /// Renders a ``CryptoMaterial`` literal for the expansion.
    private static func materialSyntax(_ material: CryptoMaterial) throws -> ExprSyntax {
        if material.entries.isEmpty {
            return "CryptoMaterial(entries: [])"
        }

        let entries = material.entries.map(cryptoEntrySyntax).joined(separator: ", ")

        return """
        CryptoMaterial(
            entries: [\(raw: entries)]
        )
        """
    }

    /// Renders one ``CryptoEntry`` literal with all masked fields.
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

    /// Renders a `[UInt8]` literal as comma-separated decimal integers.
    private static func byteArrayLiteral(_ bytes: [UInt8]) -> String {
        "[\(bytes.map(String.init).joined(separator: ", "))]"
    }
}

/// Expression macro implementation for `#Obfuscated(...)`.
public struct ObfuscatedMacro: ExpressionMacro {
    /// Expands `#Obfuscated("secret", methods: [...])` into a runtime decode call.
    ///
    /// - Parameters:
    ///   - node: Freestanding macro expansion syntax from the compiler.
    ///   - context: Macro expansion context (unused).
    /// - Returns: An expression that calls ``ObfuscatedRuntime/_decode(bytes:methods:material:)``.
    /// - Throws: ``ObfuscatedMacroError`` when arguments are invalid or encoding fails.
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let stringExpression = node.arguments.first?.expression else {
            throw ObfuscatedMacroError.missingStringLiteral
        }

        guard let string = MacroSyntaxParser.foldedStaticString(from: stringExpression) else {
            if stringExpression.is(StringLiteralExprSyntax.self) {
                throw ObfuscatedMacroError.nonStaticStringInterpolation
            }
            throw ObfuscatedMacroError.missingStringLiteral
        }

        guard let methodsArgument = node.arguments.first(where: { $0.label?.text == "methods" })?.expression else {
            throw ObfuscatedMacroError.missingMethodsArgument
        }

        let methods = try MacroSyntaxParser.parseMethods(from: methodsArgument)
        return try MacroExpansionBuilder.decodeExpression(string: string, methods: methods)
    }
}
