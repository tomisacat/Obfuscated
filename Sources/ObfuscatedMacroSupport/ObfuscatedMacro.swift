import ObfuscatedCore
import SwiftSyntax
import SwiftSyntaxMacros

/// Expression macro implementation for `#Obfuscated(...)`.
public struct ObfuscatedMacro: ExpressionMacro {
    /// Expands `#Obfuscated("secret", methods: [...])` into a runtime decode call.
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        ObfuscationMacroConfiguration.ensureRegistered()

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
