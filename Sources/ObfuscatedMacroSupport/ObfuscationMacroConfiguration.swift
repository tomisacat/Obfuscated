import Foundation
import ObfuscatedCore

/// Configures custom obfuscation step registration for a macro plugin target.
///
/// Call ``configure(registration:)`` from the plugin's initializer so steps are available
/// before any `#Obfuscated` expansion runs.
public enum ObfuscationMacroConfiguration {
    private nonisolated(unsafe) static var registration: (@Sendable () -> Void)?
    private nonisolated(unsafe) static var didRun = false
    private static let lock = NSLock()

    /// Stores and immediately runs a registration closure (typically ``ObfuscationStepRegistry/register(_:)`` calls).
    public static func configure(registration: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.registration = registration
        registration()
        didRun = true
    }

    /// Ensures registration has run before macro expansion encodes custom steps.
    static func ensureRegistered() {
        lock.lock()
        defer { lock.unlock() }
        guard !didRun, let registration else { return }
        registration()
        didRun = true
    }
}
