import ObfuscatedDemoKit
import SwiftUI

@main
struct ObfuscatedDemoApp: App {
    init() {
        ObfuscationStepRegistry.register(DemoRot13Step.self)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
