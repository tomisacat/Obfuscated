import Foundation

/// Runtime decode entry used by generated macro expansions.
///
/// Do not call directly from application code. The ``Obfuscated(_:methods:)`` macro expands to
/// calls to these decode helpers.
public enum ObfuscatedRuntime {
    /// Decodes an obfuscated string payload produced at compile time.
    public static func _decode(
        bytes: [UInt8],
        methods: [ObfuscationMethod],
        material: CryptoMaterial
    ) -> String {
        decode(bytes: bytes, methods: methods, material: material, as: String.self)
    }

    /// Decodes an obfuscated payload into any ``ObfuscatedValue`` type.
    public static func _decode<T: ObfuscatedValue>(
        bytes: [UInt8],
        methods: [ObfuscationMethod],
        material: CryptoMaterial,
        as type: T.Type = T.self
    ) -> T {
        decode(bytes: bytes, methods: methods, material: material, as: type)
    }

    /// Decodes an obfuscated ``RawRepresentable`` enum from its raw value bytes.
    public static func _decodeRawRepresentable<R: RawRepresentable>(
        bytes: [UInt8],
        methods: [ObfuscationMethod],
        material: CryptoMaterial,
        as type: R.Type
    ) -> R where R.RawValue: ObfuscatedValue {
        do {
            let payload = EncodedPayload(bytes: bytes, material: material)
            return try ObfuscationPipeline.decode(payload, methods: methods, as: type)
        } catch {
            assertionFailure("Obfuscated raw representable decode failed: \(error)")
            fatalError("Obfuscated decode failed for \(R.self)")
        }
    }

    /// Decodes an obfuscated ``CaseIterable`` enum case by name.
    public static func _decodeCaseIterable<T: CaseIterable & Sendable>(
        bytes: [UInt8],
        methods: [ObfuscationMethod],
        material: CryptoMaterial,
        caseName: String,
        as type: T.Type
    ) -> T {
        do {
            let payload = EncodedPayload(bytes: bytes, material: material)
            let decodedName = try ObfuscationPipeline.decode(payload, methods: methods, as: String.self)
            guard decodedName == caseName else {
                assertionFailure("Obfuscated enum decode failed: case name mismatch")
                return fallbackCase(for: type, caseName: caseName)
            }
            return try ObfuscatedEnumSupport.caseNamed(caseName, in: type)
        } catch {
            assertionFailure("Obfuscated enum decode failed: \(error)")
            return fallbackCase(for: type, caseName: caseName)
        }
    }

    private static func decode<T: ObfuscatedValue>(
        bytes: [UInt8],
        methods: [ObfuscationMethod],
        material: CryptoMaterial,
        as type: T.Type
    ) -> T {
        do {
            let payload = EncodedPayload(bytes: bytes, material: material)
            return try ObfuscationPipeline.decode(payload, methods: methods, as: type)
        } catch {
            assertionFailure("Obfuscated decode failed: \(error)")
            return fallbackValue(for: type)
        }
    }

    private static func fallbackValue<T: ObfuscatedValue>(for type: T.Type) -> T {
        if T.self == String.self {
            return "" as! T
        }
        if T.self == Int.self {
            return 0 as! T
        }
        if T.self == Bool.self {
            return false as! T
        }
        if T.self == Data.self {
            return Data() as! T
        }
        fatalError("Obfuscated decode failed for unsupported type \(T.self)")
    }

    private static func fallbackCase<T: CaseIterable>(for type: T.Type, caseName: String) -> T {
        if let match = T.allCases.first(where: { String(describing: $0) == caseName }) {
            return match
        }
        return T.allCases.first!
    }
}
