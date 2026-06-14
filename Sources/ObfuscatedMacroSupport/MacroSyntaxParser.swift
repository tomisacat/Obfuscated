import ObfuscatedCore
import SwiftSyntax

/// Parses macro argument syntax into runtime values used by the expansion builder.
public enum MacroSyntaxParser {
    /// Folds a string literal into a single static value, including `\("...")` segments.
    public static func foldedStaticString(from expression: ExprSyntax) -> String? {
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
    public static func stringLiteral(from expression: ExprSyntax) -> String? {
        foldedStaticString(from: expression)
    }

    /// Parses integer literal text supporting decimal, hex, octal, and binary prefixes.
    public static func parseIntegerLiteral(_ text: String) -> Int? {
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
    public static func uint8(from expression: ExprSyntax) -> UInt8? {
        guard let text = expression.as(IntegerLiteralExprSyntax.self)?.literal.text,
              let value = parseIntegerLiteral(text),
              (0 ... 255).contains(value)
        else {
            return nil
        }
        return UInt8(value)
    }

    /// Parses a signed integer literal expression.
    public static func int(from expression: ExprSyntax) -> Int? {
        guard let text = expression.as(IntegerLiteralExprSyntax.self)?.literal.text else {
            return nil
        }
        return parseIntegerLiteral(text)
    }

    /// Parses an array literal of `UInt8` integer literals.
    public static func byteArray(from expression: ExprSyntax?) -> [UInt8]? {
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
    public static func parseMethods(from expression: ExprSyntax) throws -> [ObfuscationMethod] {
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
    public static func parseMethod(from expression: ExprSyntax) throws -> ObfuscationMethod {
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
        case "custom":
            guard let idExpr = arguments["id"], let id = stringLiteral(from: idExpr) else {
                throw ObfuscatedMacroError.missingArgument("id", for: name)
            }
            guard let parameters = obfuscationParameters(from: arguments["parameters"]) else {
                throw ObfuscatedMacroError.missingArgument("parameters", for: name)
            }
            return .custom(id: id, parameters: parameters)
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

    private static func obfuscationParameters(from expression: ExprSyntax?) -> ObfuscationParameters? {
        guard let expression else { return nil }
        if let function = expression.as(FunctionCallExprSyntax.self),
           function.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "ObfuscationParameters",
           let bytesExpr = labeledArguments(in: function.arguments)["bytes"],
           let bytes = byteArray(from: bytesExpr)
        {
            return ObfuscationParameters(bytes: bytes)
        }
        if let member = expression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "init",
           let function = member.base?.as(FunctionCallExprSyntax.self),
           let bytesExpr = labeledArguments(in: function.arguments)["bytes"],
           let bytes = byteArray(from: bytesExpr)
        {
            return ObfuscationParameters(bytes: bytes)
        }
        return nil
    }

    private static func obfuscatedSalt(from expression: ExprSyntax?) -> ObfuscatedSalt? {
        obfuscatedBytesType(from: expression, typeName: "ObfuscatedSalt").map(ObfuscatedSalt.init)
    }

    private static func obfuscatedInfo(from expression: ExprSyntax?) -> ObfuscatedInfo? {
        obfuscatedBytesType(from: expression, typeName: "ObfuscatedInfo").map(ObfuscatedInfo.init)
    }

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

    private static func labeledArguments(in arguments: LabeledExprListSyntax) -> [String: ExprSyntax] {
        var result: [String: ExprSyntax] = [:]
        for argument in arguments {
            if let label = argument.label?.text {
                result[label] = argument.expression
            }
        }
        return result
    }

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
