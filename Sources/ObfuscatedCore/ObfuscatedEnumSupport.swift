import Foundation

/// Helpers for decoding ``CaseIterable`` enum cases obfuscated by case name.
public enum ObfuscatedEnumSupport {
    /// Finds a ``CaseIterable`` case whose description matches the decoded case name.
    public static func caseNamed<T: CaseIterable & Sendable>(_ name: String, in type: T.Type) throws -> T {
        if let match = T.allCases.first(where: { String(describing: $0) == name }) {
            return match
        }
        throw ObfuscationError.decodingFailed("No case named '\(name)' in \(T.self)")
    }
}
