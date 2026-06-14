import ObfuscatedCore
import SwiftSyntax
import SwiftSyntaxMacros

/// Expression macro implementation for `#Obfuscated(...)`.
public struct ObfuscatedMacro: ExpressionMacro {
    /// Expands `#Obfuscated(...)` into a runtime decode call for the payload type.
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        ObfuscationMacroConfiguration.ensureRegistered()

        guard let methodsArgument = node.arguments.first(where: { $0.label?.text == "methods" })?.expression else {
            throw ObfuscatedMacroError.missingMethodsArgument
        }

        let methods = try MacroSyntaxParser.parseMethods(from: methodsArgument)

        if let asArgument = node.arguments.first(where: { $0.label?.text == "as" })?.expression,
           let typeName = MacroSyntaxParser.typeName(from: asArgument),
           let valueArgument = node.arguments.first(where: { $0.label?.text == nil })?.expression
        {
            return try expandRawRepresentable(valueArgument, typeName: typeName, methods: methods)
        }

        guard let valueExpression = node.arguments.first?.expression else {
            throw ObfuscatedMacroError.missingValueLiteral
        }

        if let string = MacroSyntaxParser.foldedStaticString(from: valueExpression) {
            return try MacroExpansionBuilder.decodeExpression(string: string, methods: methods)
        }

        if let intValue = MacroSyntaxParser.int(from: valueExpression) {
            return try MacroExpansionBuilder.decodeExpression(value: intValue, methods: methods, as: Int.self)
        }

        if let boolValue = MacroSyntaxParser.bool(from: valueExpression) {
            return try MacroExpansionBuilder.decodeExpression(value: boolValue, methods: methods, as: Bool.self)
        }

        if let bytes = MacroSyntaxParser.byteArray(from: valueExpression) {
            return try MacroExpansionBuilder.decodeDataExpression(bytes: bytes, methods: methods)
        }

        if let (typeName, caseName) = MacroSyntaxParser.enumCaseReference(from: valueExpression) {
            return try MacroExpansionBuilder.decodeEnumCaseExpression(
                caseName: caseName,
                typeName: typeName,
                methods: methods
            )
        }

        if valueExpression.is(StringLiteralExprSyntax.self) {
            throw ObfuscatedMacroError.nonStaticStringInterpolation
        }

        throw ObfuscatedMacroError.missingValueLiteral
    }

    private static func expandRawRepresentable(
        _ expression: ExprSyntax,
        typeName: String,
        methods: [ObfuscationMethod]
    ) throws -> ExprSyntax {
        if let intValue = MacroSyntaxParser.int(from: expression) {
            return try MacroExpansionBuilder.decodeRawRepresentableExpression(
                rawValue: intValue,
                typeName: "\(typeName).self",
                methods: methods
            )
        }

        if let string = MacroSyntaxParser.foldedStaticString(from: expression) {
            return try MacroExpansionBuilder.decodeRawRepresentableExpression(
                rawValue: string,
                typeName: "\(typeName).self",
                methods: methods
            )
        }

        if expression.is(StringLiteralExprSyntax.self) {
            throw ObfuscatedMacroError.nonStaticStringInterpolation
        }

        throw ObfuscatedMacroError.missingValueLiteral
    }
}
