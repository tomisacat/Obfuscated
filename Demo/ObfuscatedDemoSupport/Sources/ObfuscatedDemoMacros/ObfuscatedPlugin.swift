import ObfuscatedCore
import ObfuscatedDemoSteps
import ObfuscatedMacroSupport
import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// Demo compiler plugin — registers ``DemoRot13Step`` for `#Obfuscated` in the demo app.
@main
struct ObfuscatedDemoPlugin: CompilerPlugin {
    init() {
        ObfuscationMacroConfiguration.configure {
            ObfuscationStepRegistry.register(DemoRot13Step.self)
        }
    }

    let providingMacros: [Macro.Type] = [
        ObfuscatedMacro.self,
    ]
}
