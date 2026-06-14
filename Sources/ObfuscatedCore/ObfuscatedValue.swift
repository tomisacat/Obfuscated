import Foundation

/// A type that can be obfuscated by serializing to bytes, running the pipeline, and deserializing at runtime.
public protocol ObfuscatedValue: Sendable {
    /// Serializes a value into plaintext bytes before obfuscation methods are applied.
    static func plaintextBytes(from value: Self) throws -> [UInt8]

    /// Reconstructs a value from plaintext bytes after the obfuscation pipeline is reversed.
    static func value(fromPlaintextBytes bytes: [UInt8]) throws -> Self
}

extension String: ObfuscatedValue {
    public static func plaintextBytes(from value: String) throws -> [UInt8] {
        guard let utf8 = value.data(using: .utf8) else {
            throw ObfuscationError.decodingFailed("Unable to encode string as UTF-8")
        }
        return Array(utf8)
    }

    public static func value(fromPlaintextBytes bytes: [UInt8]) throws -> String {
        guard let string = String(bytes: bytes, encoding: .utf8) else {
            throw ObfuscationError.decodingFailed("Unable to decode bytes as UTF-8")
        }
        return string
    }
}

extension Int: ObfuscatedValue {
    public static func plaintextBytes(from value: Int) throws -> [UInt8] {
        Int64(value).obfuscatedFixedWidthBytes
    }

    public static func value(fromPlaintextBytes bytes: [UInt8]) throws -> Int {
        let decoded = try Int64(obfuscatedFixedWidthBytes: bytes)
        guard let int = Int(exactly: decoded) else {
            throw ObfuscationError.decodingFailed("Integer value out of range for Int")
        }
        return int
    }
}

extension Bool: ObfuscatedValue {
    public static func plaintextBytes(from value: Bool) throws -> [UInt8] {
        [value ? 1 : 0]
    }

    public static func value(fromPlaintextBytes bytes: [UInt8]) throws -> Bool {
        guard bytes.count == 1 else {
            throw ObfuscationError.decodingFailed("Bool payload must be exactly one byte")
        }
        switch bytes[0] {
        case 0: return false
        case 1: return true
        default:
            throw ObfuscationError.decodingFailed("Bool payload must be 0 or 1")
        }
    }
}

extension Data: ObfuscatedValue {
    public static func plaintextBytes(from value: Data) throws -> [UInt8] {
        Array(value)
    }

    public static func value(fromPlaintextBytes bytes: [UInt8]) throws -> Data {
        Data(bytes)
    }
}

/// Encode/decode helpers for ``RawRepresentable`` types whose ``RawRepresentable/rawValue`` is an ``ObfuscatedValue``.
public enum ObfuscatedRawRepresentableSupport {
    public static func plaintextBytes<R: RawRepresentable>(from value: R) throws -> [UInt8]
    where R.RawValue: ObfuscatedValue {
        try R.RawValue.plaintextBytes(from: value.rawValue)
    }

    public static func value<R: RawRepresentable>(
        fromPlaintextBytes bytes: [UInt8],
        as type: R.Type
    ) throws -> R where R.RawValue: ObfuscatedValue {
        let raw = try R.RawValue.value(fromPlaintextBytes: bytes)
        guard let value = R(rawValue: raw) else {
            throw ObfuscationError.decodingFailed("Invalid raw value for \(R.self)")
        }
        return value
    }
}

extension Int64 {
    fileprivate var obfuscatedFixedWidthBytes: [UInt8] {
        withUnsafeBytes(of: bigEndian) { Array($0) }
    }

    fileprivate init(obfuscatedFixedWidthBytes bytes: [UInt8]) throws {
        guard bytes.count == MemoryLayout<Int64>.size else {
            throw ObfuscationError.decodingFailed("Int payload must be 8 bytes")
        }
        let value = bytes.withUnsafeBytes {
            Int64(bigEndian: $0.load(as: Int64.self))
        }
        self = value
    }
}
