/// Bitwise transforms used by lightweight ``ObfuscationMethod`` cases.
enum BitwiseObfuscator {
    /// XORs every byte with a constant key. Applying the same key again restores the input.
    ///
    /// - Parameters:
    ///   - bytes: Input byte array.
    ///   - key: Single-byte XOR mask.
    /// - Returns: Transformed bytes.
    static func xor(_ bytes: [UInt8], key: UInt8) -> [UInt8] {
        bytes.map { $0 ^ key }
    }

    /// ORs a mask into every byte. Reversed at decode time by clearing masked bits.
    ///
    /// - Parameters:
    ///   - bytes: Input byte array.
    ///   - mask: Bits to set in each byte.
    /// - Returns: Transformed bytes.
    static func bitOr(_ bytes: [UInt8], mask: UInt8) -> [UInt8] {
        bytes.map { $0 | mask }
    }

    /// Rotates each byte left by `amount` bits (mod 8).
    ///
    /// Used by ``ObfuscationMethod/bitShift(by:)`` during encode.
    ///
    /// - Parameters:
    ///   - bytes: Input byte array.
    ///   - amount: Rotation distance in bits (`1…7`).
    /// - Returns: Left-rotated bytes.
    static func rotateLeft(_ bytes: [UInt8], by amount: Int) -> [UInt8] {
        let shift = amount & 7
        guard shift != 0 else { return bytes }
        return bytes.map { byte in
            (byte << shift) | (byte >> (8 - shift))
        }
    }

    /// Rotates each byte right by `amount` bits (mod 8).
    ///
    /// Used by ``ObfuscationMethod/bitShift(by:)`` during decode.
    ///
    /// - Parameters:
    ///   - bytes: Input byte array.
    ///   - amount: Rotation distance in bits (`1…7`).
    /// - Returns: Right-rotated bytes.
    static func rotateRight(_ bytes: [UInt8], by amount: Int) -> [UInt8] {
        let shift = amount & 7
        guard shift != 0 else { return bytes }
        return bytes.map { byte in
            (byte >> shift) | (byte << (8 - shift))
        }
    }
}
