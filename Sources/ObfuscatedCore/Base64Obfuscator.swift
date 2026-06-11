import Foundation

/// Base64 encoding and decoding helpers for ``ObfuscationMethod/base64``.
enum Base64Obfuscator {
    /// Encodes raw bytes as a Base64 ASCII byte array.
    ///
    /// - Parameter bytes: Input bytes (typically UTF-8 plaintext or intermediate pipeline bytes).
    /// - Returns: The Base64 representation as UTF-8 bytes.
    static func encode(_ bytes: [UInt8]) -> [UInt8] {
        Array(Data(bytes).base64EncodedString().utf8)
    }

    /// Decodes a Base64 ASCII byte array back to raw bytes.
    ///
    /// - Parameter bytes: UTF-8 bytes containing a Base64 string.
    /// - Returns: The decoded raw bytes.
    /// - Throws: ``ObfuscationError/invalidBase64Payload`` when the input is not valid UTF-8 or Base64.
    static func decode(_ bytes: [UInt8]) throws -> [UInt8] {
        guard let string = String(bytes: bytes, encoding: .utf8),
              let data = Data(base64Encoded: string)
        else {
            throw ObfuscationError.invalidBase64Payload
        }
        return Array(data)
    }
}
