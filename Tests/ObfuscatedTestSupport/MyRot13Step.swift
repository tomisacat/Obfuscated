import ObfuscatedCore

/// Sample custom step: Caesar-style ASCII letter rotation (ROT-N).
///
/// Parameter byte 0 is the rotation amount (1…25). Non-letter bytes pass through unchanged.
/// Shared by unit tests and documented as a reference implementation in `docs/CUSTOM_OBFUSCATION_STEPS.md`.
public enum MyRot13Step: ObfuscationStep {
    public static let id = "rot13"

    public static func validate(parameters: ObfuscationParameters) throws {
        guard parameters.bytes.count == 1 else {
            throw ObfuscationError.decodingFailed("rot13 requires exactly one parameter byte")
        }
        let amount = Int(parameters.bytes[0])
        guard (1 ... 25).contains(amount) else {
            throw ObfuscationError.decodingFailed("rot13 amount must be 1…25")
        }
    }

    public static func encode(
        bytes: [UInt8],
        parameters: ObfuscationParameters,
        material: inout CryptoMaterial
    ) throws -> [UInt8] {
        let amount = Int(parameters.bytes[0])
        return bytes.map { rotateLetter($0, by: amount) }
    }

    public static func decode(
        bytes: [UInt8],
        parameters: ObfuscationParameters,
        material: inout CryptoMaterial
    ) throws -> [UInt8] {
        let amount = Int(parameters.bytes[0])
        return bytes.map { rotateLetter($0, by: 26 - amount) }
    }

    private static func rotateLetter(_ byte: UInt8, by amount: Int) -> UInt8 {
        switch byte {
        case 65 ... 90:
            let base = 65
            let offset = Int(byte) - base
            return UInt8(base + (offset + amount) % 26)
        case 97 ... 122:
            let base = 97
            let offset = Int(byte) - base
            return UInt8(base + (offset + amount) % 26)
        default:
            return byte
        }
    }
}
