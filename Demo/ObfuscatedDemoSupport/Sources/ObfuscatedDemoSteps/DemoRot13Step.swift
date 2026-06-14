import ObfuscatedCore

/// Demo custom step: ASCII letter rotation (ROT-N) registered by ``ObfuscatedDemoMacros``.
public enum DemoRot13Step: ObfuscationStep {
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
            return UInt8(65 + (Int(byte) - 65 + amount) % 26)
        case 97 ... 122:
            return UInt8(97 + (Int(byte) - 97 + amount) % 26)
        default:
            return byte
        }
    }
}
