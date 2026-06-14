import Foundation

/// Literal parameters for a custom obfuscation step, parsed from macro source.
///
/// Values must be compile-time byte literals (same constraint as ``ObfuscatedKey``).
public struct ObfuscationParameters: Sendable, Equatable, Codable {
    /// Step-specific parameter bytes embedded in the macro expansion.
    public let bytes: [UInt8]

    /// Creates parameters from explicit byte values.
    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }
}

/// Persisted state for one custom pipeline step, embedded in macro expansions.
public struct CustomMaterialEntry: Sendable, Equatable {
    /// Registry identifier matching ``ObfuscationStep/id``.
    public let id: String
    /// Step-specific bytes required to decode (e.g. masked secrets or auxiliary payload).
    public let payload: [UInt8]

    /// Creates a custom material entry.
    public init(id: String, payload: [UInt8]) {
        self.id = id
        self.payload = payload
    }
}

/// User-defined obfuscation transform registered for ``ObfuscationMethod/custom(id:parameters:)``.
///
/// Register conforming types in a macro plugin target via ``ObfuscationStepRegistry/register(_:)``
/// so compile-time encoding can invoke ``encode(bytes:parameters:material:)``.
public protocol ObfuscationStep: Sendable {
    /// Stable registry key referenced in macro source and embedded expansions.
    static var id: String { get }

    /// Validates ``ObfuscationParameters`` before encode or decode.
    static func validate(parameters: ObfuscationParameters) throws

    /// Applies the forward transform during encode.
    static func encode(
        bytes: [UInt8],
        parameters: ObfuscationParameters,
        material: inout CryptoMaterial
    ) throws -> [UInt8]

    /// Reverses the transform during decode.
    static func decode(
        bytes: [UInt8],
        parameters: ObfuscationParameters,
        material: inout CryptoMaterial
    ) throws -> [UInt8]
}

/// Registry of custom obfuscation steps available during macro expansion and runtime decode.
///
/// Populate from a user-owned macro plugin target before any `#Obfuscated` expansion runs.
public enum ObfuscationStepRegistry {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var steps: [String: any ObfuscationStep.Type] = [:]

    /// Registers a custom step type for pipeline encode/decode and macro expansion.
    public static func register(_ type: any ObfuscationStep.Type) {
        lock.lock()
        defer { lock.unlock() }
        steps[type.id] = type
    }

    /// Removes all registered custom steps (for test isolation).
    public static func reset() {
        lock.lock()
        defer { lock.unlock() }
        steps = [:]
    }

    /// Looks up a registered step by identifier.
    public static func step(for id: String) -> (any ObfuscationStep.Type)? {
        lock.lock()
        defer { lock.unlock() }
        return steps[id]
    }
}

extension CryptoMaterial {
    /// Appends custom step material in encode order.
    public mutating func appendCustomEntry(id: String, payload: [UInt8]) {
        customEntries.append(CustomMaterialEntry(id: id, payload: payload))
    }

    /// Pops the most recent custom material entry during decode.
    public mutating func popCustomEntry() throws -> CustomMaterialEntry {
        guard let entry = customEntries.popLast() else {
            throw ObfuscationError.missingCustomMaterial
        }
        return entry
    }
}
