# Obfuscated — Source Documentation

← [Back to README](../README.md)

Complete reference for every module, type, and file in the package. For diagrams and data flow, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Table of contents

1. [Package overview](#package-overview)
2. [Public API (`Obfuscated`)](#public-api-obfuscated)
3. [Core engine (`ObfuscatedCore`)](#core-engine-obfuscatedcore)
4. [Macro support (`ObfuscatedMacroSupport`)](#macro-support-obfuscatedmacrosupport)
5. [Default macro plugin (`ObfuscatedMacros`)](#default-macro-plugin-obfuscatedmacros)
6. [Custom obfuscation steps](#custom-obfuscation-steps)
7. [Obfuscation methods reference](#obfuscation-methods-reference)
8. [Crypto material model](#crypto-material-model)
9. [Encode/decode pipeline](#encodedecode-pipeline)
10. [Errors](#errors)
11. [Testing](#testing)
12. [Demo app and support package](#demo-app-and-support-package)

---

## Package overview

| Target | Visibility | Role |
|--------|------------|------|
| `Obfuscated` | **Public product** | Re-exports core types; declares `#Obfuscated` macro (default plugin) |
| `ObfuscatedCore` | **Public product** | Obfuscation pipeline, `ObfuscatedValue`, CryptoKit integration, runtime decode, custom step protocol |
| `ObfuscatedMacroSupport` | **Public product** | Shared macro parser, builder, `ObfuscatedMacro`, registration hook |
| `ObfuscatedMacros` | Compiler plugin | Default plugin; built-in methods only |
| `ObfuscatedCoreTests` | Tests | Round-trip pipeline, `ObfuscatedValue`, validation, custom step tests |
| `ObfuscatedTests` | Tests | Macro parsing, expansion, typed-value and smoke tests |
| `ObfuscatedTestSupport` | Test helper | Sample `MyRot13Step` for custom step tests |
| `ObfuscatedDemo` | Demo app (Xcode) | SwiftUI catalog; not part of the root Swift package |
| `ObfuscatedDemoSupport` | Demo local package | `ObfuscatedDemoKit` + custom macro plugin (`Demo/ObfuscatedDemoSupport/`) |

**Dependency:** [swift-syntax](https://github.com/swiftlang/swift-syntax) 603.x (macro plugin only).

**Platforms:** macOS 15+, iOS 14+, tvOS 14+, watchOS 7+, macCatalyst 14+.

---

## Public API (`Obfuscated`)

### `Sources/Obfuscated/Obfuscated.swift`

The only module consumers should `import`.

```swift
@_exported import ObfuscatedCore
```

Re-exports all public core types so `ObfuscationMethod`, `ObfuscatedKey`, etc. are available without a separate import.

#### `#Obfuscated` — expression macro (overloads)

All overloads share the same `methods:` argument. The macro inspects the **first argument** (and optional `as:`) to choose the payload type and return type.

| Overload | First argument | Return type | Expansion |
|----------|----------------|-------------|-----------|
| String | String literal (static `\("...")` allowed) | `String` | `ObfuscatedRuntime._decode(bytes:methods:material:)` |
| Int | Integer literal | `Int` | `ObfuscatedRuntime._decode(bytes:methods:material:, as: Int.self)` |
| Bool | `true` / `false` | `Bool` | `ObfuscatedRuntime._decode(bytes:methods:material:, as: Bool.self)` |
| Data | `[UInt8]` array literal | `Data` | `ObfuscatedRuntime._decode(bytes:methods:material:, as: Data.self)` |
| Enum case | `Type.case` member reference | `Enum` | `ObfuscatedRuntime._decodeCaseIterable(bytes:methods:material:caseName:as:)` |
| RawRepresentable (Int) | Integer literal + `as: Type.self` | `Enum` | `ObfuscatedRuntime._decodeRawRepresentable(bytes:methods:material:, as:)` |
| RawRepresentable (String) | String literal + `as: Type.self` | `Enum` | `ObfuscatedRuntime._decodeRawRepresentable(bytes:methods:material:, as:)` |

**Declarations:**

```swift
@freestanding(expression)
public macro Obfuscated(_ string: String, methods: [ObfuscationMethod]) -> String

@freestanding(expression)
public macro Obfuscated(_ value: Int, methods: [ObfuscationMethod]) -> Int

@freestanding(expression)
public macro Obfuscated(_ value: Bool, methods: [ObfuscationMethod]) -> Bool

@freestanding(expression)
public macro Obfuscated(_ bytes: [UInt8], methods: [ObfuscationMethod]) -> Data

@freestanding(expression)
public macro Obfuscated<Enum: CaseIterable & Sendable>(
    _ enumCase: Enum, methods: [ObfuscationMethod]
) -> Enum

@freestanding(expression)
public macro Obfuscated<Enum: RawRepresentable>(
    _ rawValue: Int, as type: Enum.Type, methods: [ObfuscationMethod]
) -> Enum

@freestanding(expression)
public macro Obfuscated<Enum: RawRepresentable>(
    _ rawValue: String, as type: Enum.Type, methods: [ObfuscationMethod]
) -> Enum
```

| Argument | Requirement |
|----------|---------------|
| Value | **Compile-time literal** — not a variable or runtime expression |
| `methods` | Array literal of `ObfuscationMethod` cases |
| `as:` | Metatype literal (e.g. `Role.self`) for `RawRepresentable` overloads only |

**String-specific:** `\(...)` is allowed only when each interpolation is a static string literal. Literal segments are folded into one plaintext string at compile time, then obfuscated together.

**Returns:** A normal value of the declared return type — callers never decode manually.

**Examples:**

```swift
let key = #Obfuscated("secret", methods: [.xor(key: 0x5A)])
let port = #Obfuscated(443, methods: [.xor(key: 0x11)])
let flag = #Obfuscated(true, methods: [.xor(key: 1)])
let blob = #Obfuscated([0xDE, 0xAD], methods: [.xor(key: 0x5A)])
let env = #Obfuscated(Environment.production, methods: [.xor(key: 0x3C)])
let role = #Obfuscated("admin", as: Role.self, methods: [.xor(key: 0x2A)])
```

**Enum semantics:**

- `Type.case` obfuscates the **case name** as UTF-8 (same as obfuscating `"production"`). Runtime decode matches `String(describing:)` against `CaseIterable.allCases`. Requires `CaseIterable` and `Sendable` — including enums that also conform to `RawRepresentable`.
- `as: Type.self` obfuscates the **raw value** bytes (`Int` → 8-byte big-endian `Int64`; `String` → UTF-8). Requires `RawRepresentable`. Use when you want the stored raw value hidden, not the case identifier string.
- **Dual conformance:** if an enum is `CaseIterable` and `RawRepresentable`, both overloads are available. `#Obfuscated(Color.red, ...)` hides the name `"red"`; `#Obfuscated(1, as: Color.self, ...)` hides the integer `1`. Pick based on which representation should not appear in the binary.
- Enums without `RawRepresentable` only support the `Type.case` overload.

See [README — Limitations](../README.md#limitations).

#### Type aliases

| Alias | Underlying type |
|-------|-----------------|
| `ObfuscatedValue` | `ObfuscatedCore.ObfuscatedValue` |
| `ObfuscationMethod` | `ObfuscatedCore.ObfuscationMethod` |
| `ObfuscatedKey` | `ObfuscatedCore.ObfuscatedKey` |
| `ObfuscatedNonce` | `ObfuscatedCore.ObfuscatedNonce` |
| `ObfuscatedSalt` | `ObfuscatedCore.ObfuscatedSalt` |
| `ObfuscatedInfo` | `ObfuscatedCore.ObfuscatedInfo` |
| `ObfuscationParameters` | `ObfuscatedCore.ObfuscationParameters` |
| `ObfuscationStep` | `ObfuscatedCore.ObfuscationStep` |
| `ObfuscationStepRegistry` | `ObfuscatedCore.ObfuscationStepRegistry` |

**Default macro:** `#Obfuscated` resolves to `ObfuscatedMacros.ObfuscatedMacro`. For custom steps, use a user-owned plugin — see [Custom obfuscation steps](#custom-obfuscation-steps) and [CUSTOM_OBFUSCATION_STEPS.md](CUSTOM_OBFUSCATION_STEPS.md).

---

## Core engine (`ObfuscatedCore`)

Public library (also re-exported through `Obfuscated`). The pipeline is usable directly for testing and tooling.

### `ObfuscationMethod.swift`

#### Material types

Wrapper structs for explicit byte material in macro arguments. All are `Sendable`, `Equatable`, and hold a `[UInt8]`.

| Type | Used by |
|------|---------|
| `ObfuscatedKey` | AES/ChaCha keys, HMAC keys, HKDF input, ECIES recipient private key |
| `ObfuscatedNonce` | AEAD nonces (12 bytes when explicit) |
| `ObfuscatedSalt` | HMAC salt, HKDF salt |
| `ObfuscatedInfo` | HKDF info parameter |

#### `ObfuscationMethod` enum

Discriminated union of every supported transform. See [Obfuscation methods reference](#obfuscation-methods-reference).

**`validate()`** — called before encode/decode. Enforces:

- `bitShift(by:)` — amount must be 1…7
- AES key — 16 or 32 bytes when explicit
- AES/ChaCha nonce — 12 bytes when explicit
- ChaCha key — 32 bytes when explicit
- HMAC key — non-empty when explicit
- HKDF input key — non-empty when explicit
- Curve25519 / P256 private key — 32 bytes when explicit

**`cryptoAlgorithm`** — maps crypto cases to `CryptoAlgorithm` for material storage.

#### `ObfuscationError`

| Case | When |
|------|------|
| `invalidShiftAmount(Int)` | `bitShift(by:)` outside 1…7 |
| `invalidAESKeySize(Int)` | AES key not 16 or 32 bytes |
| `invalidChaChaKeySize(Int)` | ChaCha key not 32 bytes |
| `invalidChaChaNonceSize(Int)` | ChaCha nonce not 12 bytes |
| `invalidHMACKeySize(Int)` | Empty HMAC key |
| `invalidHKDFInputKeySize(Int)` | Empty HKDF input |
| `invalidCurve25519PrivateKeySize(Int)` | Recipient key not 32 bytes |
| `invalidP256PrivateKeySize(Int)` | Recipient key not 32 bytes |
| `invalidBase64Payload` | Base64 decode failure |
| `missingCryptoMaterial(String)` | Decode expected a `CryptoEntry` but stack was empty |
| `unknownCustomStep(String)` | No registered `ObfuscationStep` for `.custom(id:parameters:)` |
| `missingCustomMaterial` | Decode expected a `CustomMaterialEntry` but stack was empty |
| `cryptoUnavailable` | Reserved (CryptoKit always available on supported platforms) |
| `decodingFailed(String)` | UTF-8 failure, bitOr overlap, nonce size, etc. |

---

### `ObfuscationStep.swift`

Custom obfuscation protocol and registry. See [Custom obfuscation steps](#custom-obfuscation-steps).

| Type | Role |
|------|------|
| `ObfuscationParameters` | Literal byte parameters from macro source (`ObfuscationParameters(bytes: [13])`) |
| `CustomMaterialEntry` | Per-step persisted state (`id`, `payload`) embedded in expansions |
| `ObfuscationStep` | Protocol: `id`, `validate`, `encode`, `decode` |
| `ObfuscationStepRegistry` | Thread-safe registry of step types for pipeline + macro encode |

`CryptoMaterial` extensions: `appendCustomEntry(id:payload:)`, `popCustomEntry()`.

---

---

### `ObfuscatedValue.swift`

Protocol and built-in conformances for types the macro can obfuscate. Every value is serialized to plaintext bytes before the shared pipeline runs; deserialization happens after `decodeBytes`.

#### `ObfuscatedValue` protocol

| Requirement | Purpose |
|-------------|---------|
| `plaintextBytes(from:)` | Serialize value → `[UInt8]` before encode |
| `value(fromPlaintextBytes:)` | Deserialize `[UInt8]` → value after decode |

#### Built-in conformances

| Type | Plaintext encoding |
|------|-------------------|
| `String` | UTF-8 |
| `Int` | 8-byte big-endian `Int64` |
| `Bool` | 1 byte: `0` = false, `1` = true |
| `Data` | Raw bytes (identity) |

#### `ObfuscatedRawRepresentableSupport`

Helper enum (not protocol conformance) for `RawRepresentable` types whose `RawValue` is an `ObfuscatedValue`:

- `plaintextBytes(from:)` — serializes `value.rawValue`
- `value(fromPlaintextBytes:as:)` — deserializes raw value, then `init(rawValue:)`

---

### `ObfuscatedEnumSupport.swift`

| API | Role |
|-----|------|
| `caseNamed(_:in:)` | Finds a `CaseIterable` case where `String(describing:)` matches the decoded case name |

Used by `ObfuscatedRuntime._decodeCaseIterable` after the pipeline returns the obfuscated case name string.

---

### `ObfuscationPipeline.swift`

Central encode/decode orchestrator. All value types share the same byte-level pipeline after serialization.

#### `encode(bytes:methods:) -> EncodedPayload`

1. Validate all methods.
2. Apply each method **in order** (forward) on `payload.bytes`:
   - Lightweight → transform bytes in place
   - `.custom` → look up `ObfuscationStep` in registry, call `encode`, optionally append `CustomMaterialEntry`
   - Crypto → `CryptoObfuscator.encrypt`, append `CryptoEntry` to `payload.material.entries`
3. Return `EncodedPayload`.

#### `encode<T: ObfuscatedValue>(_ value:methods:) -> EncodedPayload`

1. `T.plaintextBytes(from: value)` → `[UInt8]`
2. `encode(bytes:methods:)`

Convenience: `encode(_ string:methods:)` delegates to `String.plaintextBytes`.

#### `encode<R: RawRepresentable>(_ value:methods:)` (where `R.RawValue: ObfuscatedValue`)

Serializes via `ObfuscatedRawRepresentableSupport.plaintextBytes`, then `encode(bytes:methods:)`.

#### `decodeBytes(_:methods:) -> [UInt8]`

1. Validate all methods.
2. Apply each method **in reverse order** on bytes and material stacks (crypto pop, custom pop, lightweight inverse).
3. Return plaintext bytes (not yet deserialized to a value type).

#### `decode<T: ObfuscatedValue>(_:methods:as:) -> T`

1. `decodeBytes` → plaintext bytes
2. `T.value(fromPlaintextBytes:)` → typed value

#### `decode<R: RawRepresentable>(_:methods:as:)` (where `R.RawValue: ObfuscatedValue`)

1. `decodeBytes` → plaintext bytes
2. `ObfuscatedRawRepresentableSupport.value(fromPlaintextBytes:as:)` → enum/struct

#### `decode(_:methods:) -> String`

Convenience for `decode(..., as: String.self)`.

**Invariant:** crypto and custom entries are pushed in encode order and popped in reverse decode order. Pipeline methods must match exactly between macro expansion and runtime.

---

### `BitwiseObfuscator.swift`

`internal enum` — lightweight byte transforms.

| Function | Encode | Decode |
|----------|--------|--------|
| `xor(_:key:)` | `byte ^ key` | Same (self-inverse) |
| `bitOr(_:mask:)` | `byte \| mask` | `byte & ~mask` |
| `rotateLeft(_:by:)` | Rotate each byte left by `amount & 7` | `rotateRight` with same amount |

**`bitOr` constraint:** encode validates `(byte & mask) == 0` for every byte — mask bits must be clear in plaintext or encode throws.

---

### `Base64Obfuscator.swift`

`internal enum`.

- **encode:** `Data(bytes).base64EncodedString()` → UTF-8 bytes of the Base64 text
- **decode:** parse Base64 string → raw bytes; throws `invalidBase64Payload` on failure

---

### `CryptoMaterial.swift`

#### `CryptoAlgorithm`

String-backed enum identifying the crypto scheme stored in a `CryptoEntry`.

#### `CryptoEntry`

One crypto step's persisted state, embedded in macro expansions.

| Field | Purpose |
|-------|---------|
| `algorithm` | Which decrypt path to use |
| `payload` | Ciphertext (or HMAC-XOR'd bytes) |
| `primary` | Masked primary material (usually key or recipient private key) |
| `secondary` | Masked secondary material (HMAC salt, HKDF salt) |
| `tertiary` | Masked tertiary material (HKDF info, ECIES ephemeral public key) |
| `primaryMask`, `secondaryMask`, `tertiaryMask` | Single-byte XOR masks per field group |

**Unmasking:** `unmaskedPrimary()`, `unmaskedSecondary()`, `unmaskedTertiary()` XOR each byte array with its mask.

#### `CryptoMaterial`

```swift
public struct CryptoMaterial {
    public var entries: [CryptoEntry]
    public var customEntries: [CustomMaterialEntry]
}
```

Ordered stacks of crypto and custom entries. One entry per crypto or custom method in the pipeline.

#### `EncodedPayload`

```swift
public struct EncodedPayload {
    public var bytes: [UInt8]
    public var material: CryptoMaterial
}
```

Wire format between encode and decode.

#### `SecureRandom` (internal)

- `byte()` / `bytes(count:)` — `SecRandomCopyBytes` for masks and generated keys
- `useDeterministicValuesForTesting` — when `true`, returns `0x5A` for reproducible tests (marked `nonisolated(unsafe)`)

#### `MaskedStorage` (internal)

- `mask(_:)` — XOR entire byte array with one random mask byte; returns `(masked, mask)`
- `entry(algorithm:payload:primary:secondary:tertiary:)` — builds a `CryptoEntry` with masked fields

---

### `CryptoObfuscator.swift`

`internal enum` — all CryptoKit operations.

#### Entry points

- **`encrypt(_:method:)`** — dispatches to algorithm-specific encrypt; returns `(payload: [UInt8], entry: CryptoEntry)`
- **`decrypt(_:entry:)`** — dispatches on `entry.algorithm`

#### AES-GCM (`.aesGCM`)

- Key: explicit 16/32 bytes, or random 16 bytes
- Nonce: explicit 12 bytes, or random 12 bytes
- Seal with `AES.GCM.seal`; store combined sealed box in `payload` and masked key in `primary`

#### ChaChaPoly (`.chaChaPoly`, `.chacha20`)

- Key: explicit 32 bytes, or random 32 bytes
- Nonce: explicit 12 bytes, or random 12 bytes
- `.chacha20` is an alias — stored as `.chaChaPoly` in material

#### HMAC keystream (`.hmacSHA256`, `.hmacSHA384`, `.hmacSHA512`)

Not standard HMAC authentication — uses HMAC as a keystream generator:

1. Key (32 random bytes default) + salt (16 random bytes default)
2. `hmacKeystream` — iterates counter, HMAC(salt ‖ counter) until enough bytes
3. `payload = plaintext XOR keystream`
4. Store masked key in `primary`, masked salt in `secondary`

#### HKDF + AEAD (`.hkdfAESGCM`, `.hkdfChaChaPoly`)

1. Input key (32 random default), salt (16 random default), info (empty default)
2. `HKDF<SHA256>.deriveKey` → 32-byte symmetric key
3. Seal with AES-GCM or ChaChaPoly
4. Store input key, salt, info in `primary`, `secondary`, `tertiary`

#### ECIES (`.curve25519AESGCM`, `.p256AESGCM`)

Elliptic-curve integrated encryption:

1. Recipient private key — explicit 32 bytes, or random (deterministic in test mode)
2. Ephemeral key pair generated at encode time
3. ECDH → shared secret → HKDF-SHA256 (`sharedInfo: "Obfuscated.ECIES"`) → AES-GCM key
4. Store: sealed box in `payload`, masked recipient key in `primary`, masked ephemeral **public** key in `tertiary`
5. Decode: recipient private + ephemeral public → same symmetric key → AES-GCM open

---

### `ObfuscatedRuntime.swift`

Runtime decode entry points embedded by macro expansions. **Not for direct use.**

| Method | Used for |
|--------|----------|
| `_decode(bytes:methods:material:)` | `String` (convenience) |
| `_decode(bytes:methods:material:as:)` | Any `ObfuscatedValue` (`Int`, `Bool`, `Data`, …) |
| `_decodeRawRepresentable(bytes:methods:material:as:)` | `RawRepresentable` with `ObfuscatedValue` raw value |
| `_decodeCaseIterable(bytes:methods:material:caseName:as:)` | `CaseIterable` enum matched by case name |

**Failure behavior:**

| Type | Debug | Release |
|------|-------|---------|
| `ObfuscatedValue` | `assertionFailure`, then type-specific fallback (`""`, `0`, `false`, `Data()`) | Same fallbacks |
| `RawRepresentable` | `assertionFailure`, then `fatalError` | `fatalError` |
| `CaseIterable` enum | `assertionFailure`, then best-effort case match or `allCases.first!` | Same |

Direct use of `ObfuscationPipeline.decode` (e.g. in tests) propagates `ObfuscationError` normally.

---

## Macro support (`ObfuscatedMacroSupport`)

Shared library used by `ObfuscatedMacros` and user-owned macro plugins. Depends on `ObfuscatedCore` and swift-syntax.

### `ObfuscationMacroConfiguration.swift`

Plugin initialization hook. Call `configure(registration:)` from the plugin's `init` to register custom `ObfuscationStep` types before any expansion runs.

### `MacroSyntaxParser.swift`

Parses Swift syntax from macro arguments into `ObfuscationMethod` values.

| Helper | Parses |
|--------|--------|
| `foldedStaticString(from:)` | Folds a literal and static `\("...")` segments into one string |
| `stringLiteral(from:)` | Alias for `foldedStaticString(from:)` |
| `int(from:)` | Integer literal (decimal, hex, octal, binary) |
| `bool(from:)` | `true` / `false` boolean literal |
| `uint8(from:)` | Integer literal 0…255 (decimal, hex `0x`, octal `0o`, binary `0b`) |
| `byteArray(from:)` | `[UInt8]` array literal |
| `typeName(from:)` | Metatype in `as:` argument (e.g. `Role.self` → `"Role"`) |
| `enumCaseReference(from:)` | `Type.case` member reference → `(typeName, caseName)` |
| `parseMethods(from:)` | `[ObfuscationMethod]` array literal |
| `parseMethod(from:)` | Single method call like `.xor(key: 0x5A)` or `.custom(id: "rot13", parameters: ...)` |

**Supported method syntax in macros:**

```swift
.xor(key: 90)
.xor(key: 0x5A)
.bitShift(by: 3)
.bitOr(mask: 0x80)
.base64
.custom(id: "rot13", parameters: ObfuscationParameters(bytes: [13]))
.aesGCM(key: nil, nonce: nil)
.aesGCM(key: ObfuscatedKey(bytes: [1, 2, ...]), nonce: ObfuscatedNonce(bytes: [...]))
// ... all crypto methods with nil or explicit material
```

### `ObfuscatedMacroError.swift`

Compile-time diagnostics for malformed macro use.

### `MacroExpansionBuilder.swift`

1. `ObfuscationMacroConfiguration.ensureRegistered()` (custom steps)
2. `ObfuscationPipeline.encode` at compile time (value- or bytes-based)
3. Serializes `EncodedPayload` into Swift source:
   - `bytes: [UInt8]` literal
   - `methods: [...]` literal (reconstructed method syntax)
   - `material: CryptoMaterial(entries: [...], customEntries: [...])`
4. Emits the appropriate `ObfuscatedRuntime._decode*` call for the payload type

Typed builders: `decodeStringExpression`, `decodeTypedExpression`, `decodeDataExpression`, `decodeRawRepresentableExpression`, `decodeEnumCaseExpression`.

### `ObfuscatedMacro.swift`

`ExpressionMacro` implementation. Dispatch order in `expansion(of:in:)`:

1. If `as:` present → `RawRepresentable` (Int or String raw value literal)
2. Else if folded static string → `String`
3. Else if integer literal → `Int`
4. Else if boolean literal → `Bool`
5. Else if byte array literal → `Data`
6. Else if `Type.case` reference → `CaseIterable` enum
7. Else → `missingValueLiteral` or `nonStaticStringInterpolation`

---

## Default macro plugin (`ObfuscatedMacros`)

Thin compiler plugin entry point. Delegates expansion to `ObfuscatedMacroSupport`.

### `ObfuscatedPlugin.swift`

```swift
@main
struct ObfuscatedPlugin: CompilerPlugin {
    init() {
        ObfuscationMacroConfiguration.configure {
            // Built-in plugin: no custom steps registered by default.
        }
    }

    let providingMacros: [Macro.Type] = [
        ObfuscatedMacro.self,
    ]
}
```

---

## Custom obfuscation steps

Built-in methods live on `ObfuscationMethod`. User-defined transforms use `.custom(id:parameters:)` and conform to `ObfuscationStep`.

**Why a separate plugin target?** Macro expansion runs in a compiler plugin process that cannot import your app module. Custom step types must live in a library linked into a **user-owned macro target**, registered via `ObfuscationMacroConfiguration.configure`.

**Setup outline:**

1. Define steps conforming to `ObfuscationStep` (e.g. `DemoRot13Step`).
2. Create a `.macro` target depending on `ObfuscatedMacroSupport` and your steps library.
3. In the plugin `init`, register steps: `ObfuscationStepRegistry.register(MyStep.self)`.
4. Point `#Obfuscated` at your plugin with `#externalMacro(module: "YourMacros", type: "ObfuscatedMacro")`.
5. Register the same steps at app launch if runtime decode needs the registry (demo does this in `ObfuscatedDemoApp.init()`).

Full walkthrough: [CUSTOM_OBFUSCATION_STEPS.md](CUSTOM_OBFUSCATION_STEPS.md). Working example: `Demo/ObfuscatedDemoSupport/`.

---

## Obfuscation methods reference

### Lightweight

| Method | Parameters | Notes |
|--------|------------|-------|
| `.xor(key:)` | `UInt8` | XOR every byte |
| `.bitShift(by:)` | `Int` 1…7 | Rotate each byte left |
| `.bitOr(mask:)` | `UInt8` | OR mask into bytes; bits must be clear in plaintext |
| `.base64` | — | Base64-encode bytes as ASCII |

### Custom

| Method | Parameters | Notes |
|--------|------------|-------|
| `.custom(id:parameters:)` | `String` id, `ObfuscationParameters` | Dispatches to registered `ObfuscationStep`; requires user-owned macro plugin |

### CryptoKit AEAD

| Method | Key | Nonce | Generated defaults |
|--------|-----|-------|-------------------|
| `.aesGCM(key:nonce:)` | 16 or 32 B, or `nil` | 12 B or `nil` | 16 B key, 12 B nonce |
| `.chaChaPoly(key:nonce:)` | 32 B or `nil` | 12 B or `nil` | 32 B key, 12 B nonce |
| `.chacha20(key:nonce:)` | Alias for ChaChaPoly | | |

### HMAC keystream

| Method | Key | Salt | Generated defaults |
|--------|-----|------|-------------------|
| `.hmacSHA256(key:salt:)` | non-empty or `nil` | or `nil` | 32 B key, 16 B salt |
| `.hmacSHA384(key:salt:)` | | | |
| `.hmacSHA512(key:salt:)` | | | |

### HKDF + AEAD

| Method | inputKey | salt | info | nonce |
|--------|----------|------|------|-------|
| `.hkdfAESGCM(...)` | or `nil` → 32 B | or `nil` → 16 B | or `nil` → `[]` | AEAD nonce |
| `.hkdfChaChaPoly(...)` | | | | |

### ECIES

| Method | recipientPrivateKey | nonce |
|--------|---------------------|-------|
| `.curve25519AESGCM(...)` | 32 B or `nil` | AES-GCM nonce |
| `.p256AESGCM(...)` | 32 B or `nil` | AES-GCM nonce |

---

## Crypto material model

### What gets embedded in the binary

After macro expansion, the compiled binary contains:

1. **`bytes`** — obfuscated byte array (not the original plaintext serialization)
2. **`methods`** — array of method descriptors (for decode routing)
3. **`material.entries`** — per-crypto-step masked keys, salts, and auxiliary data
4. **`material.customEntries`** — per-custom-step persisted payload (if any)

Plaintext literals are **not** stored as their natural serialized form in the binary (unless a lightweight-only pipeline happens to produce identical bytes, which is uncommon).

### Masking scheme

Each sensitive byte array in a `CryptoEntry` is XOR'd with a single random `UInt8` mask. The mask is stored alongside the masked data. This avoids embedding raw keys next to ciphertext in the binary, though it is obfuscation — not hardware-grade protection.

### Entry field mapping by algorithm

| Algorithm | `primary` | `secondary` | `tertiary` |
|-----------|-----------|-------------|------------|
| AES-GCM | key | — | — |
| ChaChaPoly | key | — | — |
| HMAC-* | key | salt | — |
| HKDF+* | input key | salt | info |
| Curve25519 ECIES | recipient private key | — | ephemeral public key |
| P256 ECIES | recipient private key | — | ephemeral public key (x963) |

---

## Encode/decode pipeline

```
ObfuscatedValue (or raw bytes)
    │
    ▼ serialize (per-type)
Plaintext [UInt8]
    │
    ▼ encode (forward)
┌───────────────────────────────────────┐
│  xor → bitShift → bitOr → base64      │  lightweight (in-place on bytes)
│  custom (ObfuscationStep)             │  custom (append CustomMaterialEntry)
│  aesGCM → hmac → hkdf → ECIES → ...   │  crypto (append CryptoEntry each)
└───────────────────────────────────────┘
    │
    ▼
EncodedPayload { bytes, material }
    │
    ▼ embedded by macro
ObfuscatedRuntime._decode* (type-specific)
    │
    ▼ decode (reverse) → deserialize
Typed value (String, Int, Bool, Data, enum, …)
```

**Value serialization (before pipeline):**

| Source | Plaintext bytes |
|--------|-----------------|
| `String` | UTF-8 |
| `Int` | 8-byte big-endian `Int64` |
| `Bool` | `[0]` or `[1]` |
| `Data` / `[UInt8]` literal | Raw bytes |
| `Type.case` | Case name as UTF-8 string. Any `CaseIterable` enum — including `RawRepresentable` enums |
| `as: RawRepresentable` | Raw value bytes per `RawValue` type. Alternative when the enum is `RawRepresentable`; both forms may be available |

**Chaining example (string):**

```swift
#Obfuscated("secret", methods: [.xor(key: 0x11), .aesGCM(key: nil, nonce: nil), .base64])
```

Encode order: UTF-8 → XOR → AES-GCM (push entry) → Base64 ASCII bytes.

Decode order: Base64 decode → AES-GCM decrypt (pop entry) → XOR → UTF-8 string.

**Typed example (Int):**

```swift
#Obfuscated(443, methods: [.xor(key: 0x11)])
```

Encode order: `Int64(443)` big-endian bytes → XOR → obfuscated payload embedded in binary.

Decode order: XOR → 8-byte `Int64` → `Int(443)`.

---

## Errors

### Compile-time (macro)

Thrown as Swift compiler diagnostics via `ObfuscatedMacroError`:

- `missingValueLiteral` — not a supported compile-time literal
- `missingStringLiteral` — string overload given non-literal
- `nonStaticStringInterpolation` — runtime `\(...)` in string literal
- `invalidTypeExpression` — `as:` is not a metatype like `Role.self`
- Missing `methods:` argument
- Unrecognized method name
- Missing required argument labels
- `encodingFailed` — pipeline validation or transform failure during expansion

### Encode-time (macro plugin running pipeline)

Thrown during `ObfuscationPipeline.encode` inside the plugin:

- Validation failures (`ObfuscationError`)
- `bitOr` mask overlap

### Runtime (decode)

`ObfuscatedRuntime` catches errors per decode path — see [ObfuscatedRuntime](#obfuscatedruntimeswift). Typed `ObfuscatedValue` decode uses safe fallbacks in release; `RawRepresentable` and enum mismatches are stricter.

Direct use of `ObfuscationPipeline.decode` (e.g. in tests) propagates `ObfuscationError` normally.

---

## Testing

### `ObfuscatedCoreTests`

| Suite | Coverage |
|-------|----------|
| `Obfuscation pipeline` | Round-trip for every method, pipelines, unicode, empty string, pairwise lightweight combos |
| `ObfuscatedValue` | String/Int/Bool/Data serialization, round-trip through pipeline |
| `Custom obfuscation steps` | ROT13 round-trip, unknown step, invalid parameters |
| Validation | Invalid shift, key sizes, bitOr overlap |
| `Obfuscated runtime` | `_decode` returns plain string and typed values |

Uses `CryptoKit` for generating test keys in ECIES round-trips.

### `ObfuscatedTests`

| Suite | Coverage |
|-------|----------|
| `Obfuscated macros` | XOR, pipeline, interpolation, hex literal expansion snapshots |
| Typed macros | Int, Bool, Data, enum case, RawRepresentable expansion shapes |
| Custom step macros | Custom method expansion and round-trip (with `ObfuscatedTestSupport/MyRot13Step`) |
| Crypto macros | Parse + round-trip + expansion shape (with `SecureRandom.useDeterministicValuesForTesting`) |

Uses `ObfuscatedMacroSupport` directly (not the default plugin) so custom steps can be registered in tests.

---

## Demo app and support package

### Demo app

`Demo/ObfuscatedDemo/` — Xcode app (not an SPM target in the root package).

| File | Role |
|------|------|
| `ObfuscatedDemoApp.swift` | `@main` SwiftUI app entry; registers `DemoRot13Step` at launch for runtime decode |
| `ContentView.swift` | List UI with macro source, decoded value, obfuscation stats; includes **Typed Values** section |
| `DemoSecrets.swift` | All `#Obfuscated` examples and `DemoCatalog` (strings, typed values, custom ROT13) |
| `Info.plist` | iOS scene manifest + launch screen |

The Xcode project links the local package at `Demo/ObfuscatedDemoSupport/` — not the root `Obfuscated` package directly.

### Demo support package

`Demo/ObfuscatedDemoSupport/` — local SPM package depending on the root package (`path: "../.."`).

| Target | Role |
|--------|------|
| `ObfuscatedDemoSteps` | `DemoRot13Step` — sample `ObfuscationStep` (`id: "rot13"`) |
| `ObfuscatedDemoMacros` | Compiler plugin; registers `DemoRot13Step` in `ObfuscationMacroConfiguration.configure` |
| `ObfuscatedDemoKit` | Public API for the demo app; `#Obfuscated` → `ObfuscatedDemoMacros` |

**Product:** `ObfuscatedDemoKit` (imported by the demo app instead of `Obfuscated`).

**Dependency chain:** `ObfuscatedDemoKit` → `ObfuscatedCore` + `ObfuscatedDemoMacros` + `ObfuscatedDemoSteps`; macros also depend on `ObfuscatedMacroSupport`.

Builds for iOS and macOS alongside the demo app.

---

## File index

| File | Module | Visibility | Summary |
|------|--------|------------|---------|
| `Obfuscated.swift` | Obfuscated | public | Macro overload declarations, type aliases |
| `ObfuscatedValue.swift` | ObfuscatedCore | public types | `ObfuscatedValue` protocol, built-in conformances, raw-value helper |
| `ObfuscatedEnumSupport.swift` | ObfuscatedCore | public | `CaseIterable` case lookup by name |
| `ObfuscationMethod.swift` | ObfuscatedCore | public types | Methods, material structs, errors, validation |
| `ObfuscationStep.swift` | ObfuscatedCore | public types | Custom step protocol, registry, parameters |
| `ObfuscationPipeline.swift` | ObfuscatedCore | public | `encode` / `decode` |
| `CryptoMaterial.swift` | ObfuscatedCore | public types | Payload, entries, random, masking |
| `ObfuscatedRuntime.swift` | ObfuscatedCore | public | `_decode*` entry points (String, ObfuscatedValue, enum, RawRepresentable) |
| `BitwiseObfuscator.swift` | ObfuscatedCore | internal | xor, bitOr, rotate |
| `Base64Obfuscator.swift` | ObfuscatedCore | internal | Base64 encode/decode |
| `CryptoObfuscator.swift` | ObfuscatedCore | internal | CryptoKit encrypt/decrypt |
| `MacroSyntaxParser.swift` | ObfuscatedMacroSupport | internal | Macro argument parsing |
| `MacroExpansionBuilder.swift` | ObfuscatedMacroSupport | internal | Encode + emit `_decode(...)` source |
| `ObfuscatedMacro.swift` | ObfuscatedMacroSupport | macro types | `ExpressionMacro` implementation |
| `ObfuscationMacroConfiguration.swift` | ObfuscatedMacroSupport | public | Custom step registration hook |
| `ObfuscatedPlugin.swift` | ObfuscatedMacros | plugin | Default compiler plugin entry |
| `DemoRot13Step.swift` | ObfuscatedDemoSteps | demo | Sample custom step (demo package) |
| `ObfuscatedDemoKit.swift` | ObfuscatedDemoKit | demo | Demo `#Obfuscated` + typealiases (demo package) |
| `ObfuscatedPlugin.swift` | ObfuscatedDemoMacros | demo plugin | Demo compiler plugin (demo package) |

---

## Security notes

This package **obfuscates compile-time literals** in compiled binaries. It does **not**:

- Prevent determined reverse engineering
- Encrypt runtime memory
- Hide keys from a debugger attached to a running process
- Replace proper secret management (Keychain, server-side secrets)
- Obfuscate runtime variables or associated-value enum payloads

Crypto methods add significant protection over plain serialized bytes, but the decode logic and material are present in the binary. Treat as deterrence, not a vault.
