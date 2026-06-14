# Custom Obfuscation Steps

← [Back to README](../README.md)

Use the ``ObfuscationStep`` protocol to add your own transforms to `#Obfuscated(...)` at **compile time**. Built-in methods stay on ``ObfuscationMethod``; custom steps use ``ObfuscationMethod/custom(id:parameters:)``.

## Why a user macro plugin is required

`#Obfuscated` encodes strings inside a **compiler plugin** process. That plugin cannot import your app target, so custom step types must be linked into a **user-owned macro target** that registers them before expansion.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full data flow.

## 1. Implement `ObfuscationStep`

```swift
import Obfuscated

public enum MyRot13Step: ObfuscationStep {
    public static let id = "rot13"

    public static func validate(parameters: ObfuscationParameters) throws {
        guard parameters.bytes.count == 1,
              (1 ... 25).contains(Int(parameters.bytes[0]))
        else {
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
```

Put this in a library target (e.g. `MyCustomObfuscationSteps`) that depends on `Obfuscated`.

### Storing extra state

If a step needs persisted decode state, append to ``CryptoMaterial`` during encode:

```swift
material.appendCustomEntry(id: id, payload: auxiliaryBytes)
```

Pop during decode with `try material.popCustomEntry()` (LIFO, one entry per custom step).

## 2. Add a user macro plugin target

In your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/tomisacat/Obfuscated.git", from: "2.0.0"),
],
targets: [
    .target(
        name: "MyCustomObfuscationSteps",
        dependencies: [
            .product(name: "Obfuscated", package: "Obfuscated"),
        ]
    ),
    .macro(
        name: "MyAppObfuscatedMacros",
        dependencies: [
            .product(name: "ObfuscatedMacroSupport", package: "Obfuscated"),
            "MyCustomObfuscationSteps",
        ]
    ),
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "Obfuscated", package: "Obfuscated"),
            "MyAppObfuscatedMacros",
        ]
    ),
]
```

### Plugin entry point

`Sources/MyAppObfuscatedMacros/ObfuscatedPlugin.swift`:

```swift
import MyCustomObfuscationSteps
import Obfuscated
import ObfuscatedMacroSupport
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MyAppObfuscatedPlugin: CompilerPlugin {
    init() {
        ObfuscationMacroConfiguration.configure {
            ObfuscationStepRegistry.register(MyRot13Step.self)
        }
    }

    let providingMacros: [Macro.Type] = [
        ObfuscatedMacro.self,
    ]
}
```

### Point `#Obfuscated` at your plugin

In your app module (or a thin wrapper target):

```swift
@freestanding(expression)
public macro Obfuscated(
    _ string: String,
    methods: [ObfuscationMethod]
) -> String = #externalMacro(module: "MyAppObfuscatedMacros", type: "ObfuscatedMacro")
```

Import that module wherever you use `#Obfuscated`.

## 3. Use custom steps in source

```swift
let token = #Obfuscated(
    "Bearer secret",
    methods: [
        .custom(id: "rot13", parameters: ObfuscationParameters(bytes: [13])),
        .xor(key: 0x5A),
    ]
)
```

Macro syntax requires **literals**:

- `id:` — string literal matching ``ObfuscationStep/id``
- `parameters:` — `ObfuscationParameters(bytes: [13])` with integer byte literals

## Built-in-only apps

If you only use built-in ``ObfuscationMethod`` cases, keep the default `ObfuscatedMacros` plugin from the package — no extra target or registration needed.

## API reference

| Type | Role |
|------|------|
| ``ObfuscationStep`` | Protocol for encode/decode/validate |
| ``ObfuscationParameters`` | Literal byte parameters embedded in expansions |
| ``ObfuscationStepRegistry`` | Registers steps for pipeline + macro encode |
| ``ObfuscationMacroConfiguration`` | Plugin init hook to run registration |
| ``ObfuscatedMacroSupport`` | Shared parser, builder, and `ObfuscatedMacro` type |
| ``ObfuscationMethod/custom(id:parameters:)`` | Enum case used in `methods:` arrays |

## Testing

Register steps before pipeline or macro tests:

```swift
ObfuscationStepRegistry.reset()
ObfuscationStepRegistry.register(MyRot13Step.self)
ObfuscationMacroConfiguration.configure {
    ObfuscationStepRegistry.register(MyRot13Step.self)
}
```

See `Tests/ObfuscatedCoreTests/CustomObfuscationStepTests.swift` and `Tests/ObfuscatedTests/ObfuscatedMacroTests.swift` for examples.

## Working example in this repo

The demo app uses a local package at [`Demo/ObfuscatedDemoSupport`](../Demo/ObfuscatedDemoSupport/) with the same layout as above: `ObfuscatedDemoSteps` (custom steps), `ObfuscatedDemoMacros` (plugin registration), and `ObfuscatedDemoKit` (public `#Obfuscated` pointing at the demo plugin).
