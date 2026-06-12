# Obfuscated — Source Documentation

← [Back to README](../README.md)

Complete reference for every module, type, and file in the package. For diagrams and data flow, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Table of contents

1. [Package overview](#package-overview)
2. [Public API (`Obfuscated`)](#public-api-obfuscated)
3. [Core engine (`ObfuscatedCore`)](#core-engine-obfuscatedcore)
4. [Macro plugin (`ObfuscatedMacros`)](#macro-plugin-obfuscatedmacros)
5. [Obfuscation methods reference](#obfuscation-methods-reference)
6. [Crypto material model](#crypto-material-model)
7. [Encode/decode pipeline](#encodedecode-pipeline)
8. [Errors](#errors)
9. [Testing](#testing)
10. [Demo app](#demo-app)

---

## Package overview

| Target | Visibility | Role |
|--------|------------|------|
| `Obfuscated` | **Public product** | Re-exports core types; declares `#Obfuscated` macro |
| `ObfuscatedCore` | Internal (types re-exported) | Obfuscation pipeline, CryptoKit integration, runtime decode |
| `ObfuscatedMacros` | Compiler plugin | Parses macro syntax, runs encode at compile time, emits expansion |
| `ObfuscatedCoreTests` | Tests | Round-trip and validation tests for the pipeline |
| `ObfuscatedTests` | Tests | Macro parsing, expansion, and smoke tests |
| `ObfuscatedDemo` | Demo app (Xcode) | SwiftUI catalog; not part of the Swift package product |

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

#### `#Obfuscated` — expression macro

```swift
@freestanding(expression)
public macro Obfuscated(
    _ string: String,
    methods: [ObfuscationMethod]
) -> String
```

| Argument | Requirement |
|----------|---------------|
| `string` | **String literal** (not a variable). `\(...)` is allowed only when each interpolation is a static string literal. |
| `methods` | Array literal of `ObfuscationMethod` cases |

**Expands to:** a single `ObfuscatedRuntime._decode(bytes:methods:material:)` call. Literal segments and static `\("...")` interpolations are folded into one plaintext string at compile time, then obfuscated together.

**Returns:** `String` — callers never decode manually.

**Static interpolation example:**

```swift
let header = #Obfuscated("Bearer \("abc")", methods: [.xor(key: 0x5A)])
// folds to "Bearer abc", then expands to one _decode(...) call
```

#### Type aliases

| Alias | Underlying type |
|-------|-----------------|
| `ObfuscationMethod` | `ObfuscatedCore.ObfuscationMethod` |
| `ObfuscatedKey` | `ObfuscatedCore.ObfuscatedKey` |
| `ObfuscatedNonce` | `ObfuscatedCore.ObfuscatedNonce` |
| `ObfuscatedSalt` | `ObfuscatedCore.ObfuscatedSalt` |
| `ObfuscatedInfo` | `ObfuscatedCore.ObfuscatedInfo` |

---

## Core engine (`ObfuscatedCore`)

Internal implementation. Public types are re-exported through `Obfuscated`. The pipeline is also usable directly for testing and tooling.

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
| `cryptoUnavailable` | Reserved (CryptoKit always available on supported platforms) |
| `decodingFailed(String)` | UTF-8 failure, bitOr overlap, nonce size, etc. |

---

### `ObfuscationPipeline.swift`

Central encode/decode orchestrator.

#### `encode(_:methods:) -> EncodedPayload`

1. Validate all methods.
2. Convert `String` → UTF-8 `[UInt8]`.
3. Apply each method **in order** (forward):
   - Lightweight → transform `payload.bytes` in place
   - Crypto → `CryptoObfuscator.encrypt`, append `CryptoEntry` to `payload.material.entries`
4. Return `EncodedPayload`.

#### `decode(_:methods:) -> String`

1. Validate all methods.
2. Apply each method **in reverse order**:
   - Crypto → `popLast()` from `material.entries`, `CryptoObfuscator.decrypt`
   - Lightweight → inverse transform
3. Convert bytes → `String` (UTF-8).

**Invariant:** crypto entries are pushed in encode order and popped in reverse decode order. Pipeline methods must match exactly between macro expansion and runtime.

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
}
```

Ordered stack of crypto entries. One entry per crypto method in the pipeline.

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

```swift
public enum ObfuscatedRuntime {
    public static func _decode(
        bytes: [UInt8],
        methods: [ObfuscationMethod],
        material: CryptoMaterial
    ) -> String
}
```

**Not for direct use.** Embedded by macro expansions. On decode failure: `assertionFailure` in debug, returns `""` in release.

---

## Macro plugin (`ObfuscatedMacros`)

Runs at compile time in a separate plugin process. Depends on `ObfuscatedCore` and swift-syntax.

### `ObfuscatedPlugin.swift`

```swift
@main
struct ObfuscatedPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ObfuscatedMacro.self,
    ]
}
```

### `ObfuscatedMacro.swift`

#### `MacroSyntaxParser` (internal)

Parses Swift syntax from macro arguments into `ObfuscationMethod` values.

| Helper | Parses |
|--------|--------|
| `foldedStaticString(from:)` | Folds a literal and static `\("...")` segments into one string |
| `stringLiteral(from:)` | Alias for ``foldedStaticString(from:)`` |
| `uint8(from:)` | Integer literal 0…255 (decimal, hex `0x`, octal `0o`, binary `0b`) |
| `byteArray(from:)` | `[UInt8]` array literal |
| `parseMethods(from:)` | `[ObfuscationMethod]` array literal |
| `parseMethod(from:)` | Single method call like `.xor(key: 0x5A)` |

**Supported method syntax in macros:**

```swift
.xor(key: 90)
.xor(key: 0x5A)
.bitShift(by: 3)
.bitOr(mask: 0x80)
.base64
.aesGCM(key: nil, nonce: nil)
.aesGCM(key: ObfuscatedKey(bytes: [1, 2, ...]), nonce: ObfuscatedNonce(bytes: [...]))
// ... all crypto methods with nil or explicit material
```

#### `ObfuscatedMacroError` (internal)

Compile-time diagnostics for malformed macro use. See error messages in `description`.

#### `MacroExpansionBuilder` (internal)

1. `ObfuscationPipeline.encode(string, methods:)` at compile time
2. Serializes `EncodedPayload` into Swift source:
   - `bytes: [UInt8]` literal
   - `methods: [...]` literal (reconstructed method syntax)
   - `material: CryptoMaterial(entries: [...])` with full `CryptoEntry` literals

#### `ObfuscatedMacro` — `ExpressionMacro`

Parses `#Obfuscated("...", methods: [...])` → returns `ObfuscatedRuntime._decode(...)` expression.

---

## Obfuscation methods reference

### Lightweight

| Method | Parameters | Notes |
|--------|------------|-------|
| `.xor(key:)` | `UInt8` | XOR every byte |
| `.bitShift(by:)` | `Int` 1…7 | Rotate each byte left |
| `.bitOr(mask:)` | `UInt8` | OR mask into bytes; bits must be clear in plaintext |
| `.base64` | — | Base64-encode bytes as ASCII |

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

1. **`bytes`** — obfuscated byte array (not the original UTF-8 string)
2. **`methods`** — array of method descriptors (for decode routing)
3. **`material.entries`** — per-crypto-step masked keys, salts, and auxiliary data

Plaintext string literals are **not** stored as contiguous UTF-8 in the binary (unless a lightweight-only pipeline happens to produce identical bytes, which is uncommon).

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
String (UTF-8)
    │
    ▼ encode (forward)
┌───────────────────────────────────────┐
│  xor → bitShift → bitOr → base64      │  lightweight (in-place on bytes)
│  aesGCM → hmac → hkdf → ECIES → ...   │  crypto (append CryptoEntry each)
└───────────────────────────────────────┘
    │
    ▼
EncodedPayload { bytes, material }
    │
    ▼ embedded by macro
ObfuscatedRuntime._decode(bytes, methods, material)
    │
    ▼ decode (reverse)
String (UTF-8)
```

**Chaining example:**

```swift
#Obfuscated("secret", methods: [.xor(key: 0x11), .aesGCM(key: nil, nonce: nil), .base64])
```

Encode order: UTF-8 → XOR → AES-GCM (push entry) → Base64 ASCII bytes.

Decode order: Base64 decode → AES-GCM decrypt (pop entry) → XOR → UTF-8 string.

---

## Errors

### Compile-time (macro)

Thrown as Swift compiler diagnostics via `ObfuscatedMacroError`:

- Non-literal string
- Missing `methods:` argument
- Unrecognized method name
- Missing required argument labels

### Encode-time (macro plugin running pipeline)

Thrown during `ObfuscationPipeline.encode` inside the plugin:

- Validation failures (`ObfuscationError`)
- `bitOr` mask overlap

### Runtime (decode)

`ObfuscatedRuntime._decode` catches all errors:

- **Debug:** `assertionFailure` with error description
- **Release:** returns empty string `""`

Direct use of `ObfuscationPipeline.decode` (e.g. in tests) propagates `ObfuscationError` normally.

---

## Testing

### `ObfuscatedCoreTests`

| Suite | Coverage |
|-------|----------|
| `Obfuscation pipeline` | Round-trip for every method, pipelines, unicode, empty string, pairwise lightweight combos |
| Validation | Invalid shift, key sizes, bitOr overlap |
| `Obfuscated runtime` | `_decode` returns plain string |

Uses `CryptoKit` for generating test keys in ECIES round-trips.

### `ObfuscatedTests`

| Suite | Coverage |
|-------|----------|
| `Obfuscated macros` | XOR, pipeline, interpolation, hex literal expansion snapshots |
| Crypto macros | Parse + round-trip + expansion shape (with `SecureRandom.useDeterministicValuesForTesting`) |

---

## Demo app

`Demo/ObfuscatedDemo/` — Xcode project (not SPM target).

| File | Role |
|------|------|
| `ObfuscatedDemoApp.swift` | `@main` SwiftUI app entry |
| `ContentView.swift` | List UI with macro source, decoded value, obfuscation stats |
| `DemoSecrets.swift` | All `#Obfuscated` examples and `DemoCatalog` |
| `Info.plist` | iOS scene manifest + launch screen |

Links the local `Obfuscated` package at `../`. Builds for iOS and macOS.

---

## File index

| File | Module | Visibility | Summary |
|------|--------|------------|---------|
| `Obfuscated.swift` | Obfuscated | public | Macro declarations, type aliases |
| `ObfuscationMethod.swift` | ObfuscatedCore | public types | Methods, material structs, errors, validation |
| `ObfuscationPipeline.swift` | ObfuscatedCore | public | `encode` / `decode` |
| `CryptoMaterial.swift` | ObfuscatedCore | public types | Payload, entries, random, masking |
| `ObfuscatedRuntime.swift` | ObfuscatedCore | public | `_decode` entry point |
| `BitwiseObfuscator.swift` | ObfuscatedCore | internal | xor, bitOr, rotate |
| `Base64Obfuscator.swift` | ObfuscatedCore | internal | Base64 encode/decode |
| `CryptoObfuscator.swift` | ObfuscatedCore | internal | CryptoKit encrypt/decrypt |
| `ObfuscatedPlugin.swift` | ObfuscatedMacros | plugin | Compiler plugin entry |
| `ObfuscatedMacro.swift` | ObfuscatedMacros | macro types | Parser, builder, macro implementations |

---

## Security notes

This package **obfuscates** string literals in compiled binaries. It does **not**:

- Prevent determined reverse engineering
- Encrypt runtime memory
- Hide keys from a debugger attached to a running process
- Replace proper secret management (Keychain, server-side secrets)

Crypto methods add significant protection over plain UTF-8, but the decode logic and material are present in the binary. Treat as deterrence, not a vault.
