import ObfuscatedMacroSupport
import SwiftSyntax
import SwiftSyntaxMacros

/// Demo macro implementation — forwards to ``ObfuscatedMacroSupport/ObfuscatedMacro`` after registration.
public struct ObfuscatedMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        try ObfuscatedMacroSupport.ObfuscatedMacro.expansion(of: node, in: context)
    }
}
