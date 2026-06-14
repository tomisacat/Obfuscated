import ObfuscatedMacroSupport
import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// Compiler plugin entry point that registers the Obfuscated macro implementation.
@main
struct ObfuscatedPlugin: CompilerPlugin {
    init() {
        ObfuscationMacroConfiguration.configure {
            // Built-in plugin: no custom steps registered by default.
        }
    }

    /// Macros provided by this plugin to the Swift compiler.
    let providingMacros: [Macro.Type] = [
        ObfuscatedMacro.self,
    ]
}
