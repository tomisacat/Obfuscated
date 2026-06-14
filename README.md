# Obfuscated

<p align="center">
  <a href="https://github.com/tomisacat/Obfuscated/actions/workflows/ci.yml">
    <img src="https://github.com/tomisacat/Obfuscated/actions/workflows/ci.yml/badge.svg" alt="CI">
  </a>
  <a href="https://github.com/tomisacat/Obfuscated/releases">
    <img src="https://img.shields.io/github/v/release/tomisacat/Obfuscated?label=release" alt="Release">
  </a>
  <img src="https://img.shields.io/badge/Swift-6.2+-orange.svg" alt="Swift 6.2+">
  <img src="https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20tvOS%20%7C%20watchOS-lightgrey" alt="Platforms">
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License">
  </a>
</p>

Compile-time value obfuscation for Swift via freestanding macros.

Use `#Obfuscated(...)` with a **compile-time literal** and get a normal value back — `String`, `Int`, `Bool`, `Data`, or enum — with no wrapper type, no manual decode, and no extra setup. Obfuscation happens at build time; the rest of your code treats the result like any ordinary value.

## Showcase

The included demo app exercises every built-in obfuscation method, typed value examples (Int, Bool, Data, enums), a custom ROT13 step, and verifies compile-time bytes differ from plaintext.

<p align="center">
  <img src="docs/images/Obfuscated.png" alt="Obfuscated Demo on iPhone — macro source, decoded value, and runtime checks for HKDF and ECIES methods" width="320">
</p>

Open [`Demo/ObfuscatedDemo.xcodeproj`](Demo/ObfuscatedDemo.xcodeproj) to run the catalog on iOS or macOS. The app imports **ObfuscatedDemoKit** from the local package at [`Demo/ObfuscatedDemoSupport`](Demo/ObfuscatedDemoSupport/) — not the root `Obfuscated` product directly — so custom steps work in the demo.

## Requirements

- Swift 6.2+
- macOS 15+, iOS 14+, tvOS 14+, watchOS 7+, macCatalyst 14+
- Xcode 16+ (macro plugin support)

## Installation

Add the package to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/tomisacat/Obfuscated.git", from: "2.1.0"),
],
targets: [
    .target(
        name: "<YourAppTarget>",
        dependencies: ["Obfuscated"]
    ),
]
```

For an Xcode app target, use **File → Add Package Dependencies** and enter `https://github.com/tomisacat/Obfuscated.git`.

### Products


| Product                  | Use when                                                               |
| ------------------------ | ---------------------------------------------------------------------- |
| `Obfuscated`             | Default — built-in methods only; `#Obfuscated` via `ObfuscatedMacros`  |
| `ObfuscatedCore`         | Direct pipeline access, tests, or custom step libraries                |
| `ObfuscatedMacroSupport` | Building a user-owned macro plugin with custom `ObfuscationStep` types |


Built-in-only apps need only `Obfuscated`. Custom steps require a separate macro plugin target — see [Custom obfuscation steps](#custom-obfuscation-steps).

## Quick start

From the caller's perspective, nothing about obfuscation is visible after expansion:

```swift
import Obfuscated

let apiKey = #Obfuscated("secret-api-key", methods: [.xor(key: 0x5A), .base64])

// apiKey is String — not ObfuscatedString, not Data, not Optional
request.setHeader("Authorization", value: "Bearer \(apiKey)")
```

The macro accepts **compile-time literals** only — not variables. Supported payload types:

| Type | Example |
|------|---------|
| `String` | `#Obfuscated("secret", methods: [...])` |
| `Int` | `#Obfuscated(443, methods: [...])` |
| `Bool` | `#Obfuscated(true, methods: [...])` |
| `Data` | `#Obfuscated([0xDE, 0xAD], methods: [...])` |
| Enum case | `#Obfuscated(Environment.production, methods: [...])` — `CaseIterable` (hides case **name**) |
| `RawRepresentable` | `#Obfuscated(1, as: Color.self, methods: [...])` — hides **raw value** |

String literals with static interpolations are folded at compile time, then obfuscated as one string:

```swift
let header = #Obfuscated("Bearer \("my-token")", methods: [.xor(key: 0x33)])
// equivalent to #Obfuscated("Bearer my-token", methods: [...])
```

`\(...)` works when the interpolation is another string literal (e.g. `\("token")`), not a runtime value like `\(userToken)`.

### Typed value examples

```swift
let port: Int = #Obfuscated(443, methods: [.xor(key: 0x11)])
let enabled: Bool = #Obfuscated(true, methods: [.xor(key: 1)])
let token: Data = #Obfuscated([0xDE, 0xAD, 0xBE, 0xEF], methods: [.xor(key: 0x5A)])

enum Environment: CaseIterable { case production, staging }
let env: Environment = #Obfuscated(Environment.production, methods: [.xor(key: 0x3C)])

enum Role: String, CaseIterable { case admin, guest }
let role: Role = #Obfuscated("admin", as: Role.self, methods: [.xor(key: 0x2A)])

// Int-backed + CaseIterable: either form works — they hide different things
enum Color: Int, CaseIterable { case red = 1, blue = 2 }
let byName = #Obfuscated(Color.red, methods: [.xor(key: 0x7)])      // hides "red"
let byRawValue = #Obfuscated(1, as: Color.self, methods: [.xor(key: 0x7)]) // hides 1
```

**Enum notes:** See [Limitations](#limitations) for when to use `Type.case` vs `as: Type.self`, and which enum kinds support each form.

## Limitations

`#Obfuscated` only works with **compile-time literals** — not variables or runtime expressions. Full discussion: [docs/RELEASE_NOTES/v2.1.0.md — Limitations](docs/RELEASE_NOTES/v2.1.0.md#limitations).

| Caveat | Detail |
|--------|--------|
| Literals only | Pass string, integer, boolean, byte-array, or enum-case **literals** — not `let x` or other runtime values |
| String interpolation | `\(...)` is allowed only when each segment is a static string literal (e.g. `\("token")`) |
| `Type.case` | Obfuscates the **case name** as UTF-8. Requires `CaseIterable` and `Sendable`. Works for **any** `CaseIterable` enum — including `Int` or `String`-backed enums that also conform to `RawRepresentable` |
| `as: Type.self` | Obfuscates the **raw value** (`Int` → 8-byte `Int64`, `String` → UTF-8). Requires `RawRepresentable`. Use when you want the stored raw value hidden |
| Both overloads | If an enum is `CaseIterable` **and** `RawRepresentable`, you may use either form — `#Obfuscated(Color.red, ...)` hides the name `"red"`; `#Obfuscated(1, as: Color.self, ...)` hides the integer `1` |
| No raw value | Enums without `RawRepresentable` (e.g. `Environment.production`) only support the `Type.case` form — there is no `as:` overload for them |
| Associated values | Enum cases with associated values are not supported |

The demo shows three shapes: `DemoEnvironment` (`CaseIterable` only), `DemoRole` (string raw value via `as:`), `DemoColor` (int raw value via `as:` — not `CaseIterable`, so `Type.case` is unavailable there). See [`DemoSecrets.swift`](Demo/ObfuscatedDemo/DemoSecrets.swift).

## Architecture

Obfuscation happens at **compile time**; runtime only reverses the embedded byte payload. The root package splits into four layers:


| Layer          | Module                   | Role                                                          |
| -------------- | ------------------------ | ------------------------------------------------------------- |
| Public API     | `Obfuscated`             | `#Obfuscated` macro, re-exported core types                   |
| Macro support  | `ObfuscatedMacroSupport` | Shared parser, builder, registration hook                     |
| Default plugin | `ObfuscatedMacros`       | Built-in methods only                                         |
| Core           | `ObfuscatedCore`         | Encode/decode pipeline, `ObfuscatedValue`, CryptoKit, custom steps |


Custom steps use a **user-owned macro plugin** that links `ObfuscatedMacroSupport` and registers step types before expansion. The demo implements this in `[Demo/ObfuscatedDemoSupport](Demo/ObfuscatedDemoSupport/)` (`ObfuscatedDemoKit` + `ObfuscatedDemoMacros` + `ObfuscatedDemoSteps`).

Diagrams and data flow: **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** · Full API reference: **[docs/DOCUMENTATION.md](docs/DOCUMENTATION.md)**

## Obfuscation methods


| Category       | Methods                                                                   |
| -------------- | ------------------------------------------------------------------------- |
| Lightweight    | `.xor(key:)`, `.bitShift(by:)`, `.bitOr(mask:)`, `.base64`                |
| Custom         | `.custom(id:parameters:)` — requires user-owned macro plugin              |
| AEAD           | `.aesGCM(key:nonce:)`, `.chaChaPoly(key:nonce:)`, `.chacha20(key:nonce:)` |
| HMAC keystream | `.hmacSHA256(key:salt:)`, `.hmacSHA384`, `.hmacSHA512`                    |
| HKDF + AEAD    | `.hkdfAESGCM(...)`, `.hkdfChaChaPoly(...)`                                |
| ECIES          | `.curve25519AESGCM(recipientPrivateKey:nonce:)`, `.p256AESGCM(...)`       |


Pass `nil` for crypto key material to generate random values at compile time. Pass explicit `ObfuscatedKey`, `ObfuscatedNonce`, `ObfuscatedSalt`, or `ObfuscatedInfo` for reproducible output.

Methods chain left-to-right at encode time and reverse at decode time.

## Custom obfuscation steps

Implement the `ObfuscationStep` protocol and register your step in a **macro plugin target** so `#Obfuscated` can encode it at compile time. Macro expansion runs in a plugin process that cannot import your app module, so custom steps must live in a library linked into that plugin.

```swift
// In your app (after registering steps at launch for runtime decode):
let secret = #Obfuscated(
    "Custom protected secret",
    methods: [.custom(id: "rot13", parameters: ObfuscationParameters(bytes: [13]))]
)
```

**Setup outline:**

1. Implement `ObfuscationStep` (see [`DemoRot13Step.swift`](Demo/ObfuscatedDemoSupport/Sources/ObfuscatedDemoSteps/DemoRot13Step.swift))
2. Add a `.macro` target depending on `ObfuscatedMacroSupport` and your steps library
3. Register in the plugin `init`: `ObfuscationStepRegistry.register(MyRot13Step.self)`
4. Point `#Obfuscated` at your plugin with `#externalMacro(module: "YourMacros", type: "ObfuscatedMacro")`
5. Register the same steps at app launch so runtime decode can find them

Built-in-only apps use the default `Obfuscated` product. The demo uses **ObfuscatedDemoKit** from [`Demo/ObfuscatedDemoSupport`](Demo/ObfuscatedDemoSupport/), which wires in `ObfuscatedDemoMacros` with `DemoRot13Step` pre-registered.

Full walkthrough: **[docs/CUSTOM_OBFUSCATION_STEPS.md](docs/CUSTOM_OBFUSCATION_STEPS.md)**

## Documentation


| Document                                                             | Contents                                                       |
| -------------------------------------------------------------------- | -------------------------------------------------------------- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)                         | Mermaid diagrams and system data flow                          |
| [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md)                       | Full source reference — every module, type, and algorithm      |
| [docs/CUSTOM_OBFUSCATION_STEPS.md](docs/CUSTOM_OBFUSCATION_STEPS.md) | User-defined `ObfuscationStep` protocol and macro plugin setup |
| [docs/RELEASE_NOTES/v2.1.0.md](docs/RELEASE_NOTES/v2.1.0.md)         | 2.1.0 release notes (typed values: Int, Bool, Data, enums)     |
| [docs/RELEASE_NOTES/v2.0.0.md](docs/RELEASE_NOTES/v2.0.0.md)         | 2.0.0 release notes (custom steps, breaking changes)           |
| [docs/RELEASE_NOTES/v1.0.0.md](docs/RELEASE_NOTES/v1.0.0.md)         | Initial release notes                                          |


## Testing

```bash
swift test
```

- `ObfuscatedCoreTests` — encode/decode round-trips, typed values, validation, custom step pipeline tests
- `ObfuscatedTests` — macro parsing, expansion, typed-value and custom step smoke tests

Build the demo support package:

```bash
cd Demo/ObfuscatedDemoSupport && swift build
```

## Package layout

Root Swift package (published library):

```
Sources/
  Obfuscated/              Public API (#Obfuscated → ObfuscatedMacros)
  ObfuscatedCore/          Encode/decode pipeline, ObfuscatedValue, CryptoKit, ObfuscationStep
  ObfuscatedMacroSupport/  Shared macro parser, builder, registration hook
  ObfuscatedMacros/        Default compiler plugin (built-in methods only)
Tests/
  ObfuscatedCoreTests/
  ObfuscatedTests/
  ObfuscatedTestSupport/   Sample MyRot13Step for custom step tests
```

Demo (not part of the published package):

```
Demo/
  ObfuscatedDemo/          SwiftUI app (Xcode project)
  ObfuscatedDemoSupport/   Local SPM package
    ObfuscatedDemoKit      Demo public API (#Obfuscated → ObfuscatedDemoMacros)
    ObfuscatedDemoMacros   Demo compiler plugin (registers DemoRot13Step)
    ObfuscatedDemoSteps    DemoRot13Step implementation
```

## License

MIT License. See [LICENSE](LICENSE).
