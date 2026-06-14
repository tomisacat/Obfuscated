import Foundation

/// Errors surfaced during macro argument parsing and compile-time encoding.
public enum ObfuscatedMacroError: Error, CustomStringConvertible {
    /// The macro was not given a compile-time literal as its payload.
    case missingValueLiteral
    /// The macro was not given a string literal as its payload.
    case missingStringLiteral
    /// A `\(...)` segment is not a static string literal.
    case nonStaticStringInterpolation
    /// The macro call is missing a `methods:` argument.
    case missingMethodsArgument
    /// The `methods:` argument is not an array literal of supported method calls.
    case invalidMethodsExpression
    /// A method name or syntax shape is not supported by the parser.
    case unsupportedMethod(String)
    /// A required labeled argument is missing from a method call.
    case missingArgument(String, for: String)
    /// ``ObfuscationPipeline/encode(_:methods:)`` failed while expanding the macro.
    case encodingFailed(String)
    /// The `as:` argument is not a valid metatype expression (e.g. `MyEnum.self`).
    case invalidTypeExpression

    /// Human-readable diagnostic text shown at the macro use site.
    public var description: String {
        switch self {
        case .missingValueLiteral:
            "#Obfuscated requires a compile-time literal (string, integer, boolean, byte array, enum case, or raw value with `as:`)"
        case .missingStringLiteral:
            "#Obfuscated requires a string literal (variables are not supported)"
        case .nonStaticStringInterpolation:
            "#Obfuscated interpolation must be a string literal, e.g. \"Bearer \\(\"token\")\""
        case .missingMethodsArgument:
            "#Obfuscated requires a `methods:` argument"
        case .invalidMethodsExpression:
            "`methods:` must be an array literal of obfuscation methods"
        case .unsupportedMethod(let method):
            "Unsupported obfuscation method: \(method)"
        case .missingArgument(let argument, let method):
            "Missing `\(argument)` argument for `\(method)`"
        case .encodingFailed(let message):
            "Failed to obfuscate value: \(message)"
        case .invalidTypeExpression:
            "`as:` must be a metatype literal such as `MyEnum.self`"
        }
    }
}
