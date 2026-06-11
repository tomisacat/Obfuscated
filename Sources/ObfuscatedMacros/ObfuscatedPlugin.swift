import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// Compiler plugin entry point that registers the Obfuscated macro implementation.
@main
struct ObfuscatedPlugin: CompilerPlugin {
    /// Macros provided by this plugin to the Swift compiler.
    let providingMacros: [Macro.Type] = [
        ObfuscatedMacro.self,
    ]
}
