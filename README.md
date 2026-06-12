# Obfuscated

Compile-time string obfuscation for Swift via freestanding macros.

Use `#Obfuscated("secret", methods: [...])` and get a normal `String` back — no wrapper type, no manual decode, no extra setup. Obfuscation happens at build time; the rest of your code treats the value like any other string.

## Showcase

The included demo app exercises every obfuscation method and verifies compile-time bytes differ from the plain UTF-8 literal.

<p align="center">
  <img src="docs/images/Obfuscated.png" alt="Obfuscated Demo on iPhone — macro source, decoded value, and runtime checks for HKDF and ECIES methods" width="320">
</p>

Open [`Demo/ObfuscatedDemo.xcodeproj`](Demo/ObfuscatedDemo.xcodeproj) to run the catalog on iOS or macOS.

## Requirements

- Swift 6.2+
- macOS 15+, iOS 14+, tvOS 14+, watchOS 7+, macCatalyst 14+
- Xcode 16+ (macro plugin support)

## Installation

Add the package to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/tomisacat/Obfuscated.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: ["Obfuscated"]
    ),
]
```

For an Xcode app target, use **File → Add Package Dependencies** and enter `https://github.com/tomisacat/Obfuscated.git`.

## Quick start

From the caller's perspective, nothing about obfuscation is visible after expansion:

```swift
import Obfuscated

let apiKey = #Obfuscated("secret-api-key", methods: [.xor(key: 0x5A), .base64])

// apiKey is String — not ObfuscatedString, not Data, not Optional
request.setHeader("Authorization", value: "Bearer \(apiKey)")
```

String literals with static interpolations are folded at compile time, then obfuscated as one string:

```swift
let header = #Obfuscated("Bearer \("my-token")", methods: [.xor(key: 0x33)])
// equivalent to #Obfuscated("Bearer my-token", methods: [...])
```

The macro accepts string literals only — not variables. `\(...)` works when the interpolation is another string literal (e.g. `\("token")`), not a runtime value like `\(userToken)`.

## Architecture

Obfuscation happens at **compile time**; runtime only reverses the embedded byte payload. The package splits into three layers: public macros, a compiler plugin, and a shared encode/decode core.

Full diagrams and walkthroughs are in **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**:

## Obfuscation methods

| Category | Methods |
|----------|---------|
| Lightweight | `.xor(key:)`, `.bitShift(by:)`, `.bitOr(mask:)`, `.base64` |
| AEAD | `.aesGCM(key:nonce:)`, `.chaChaPoly(key:nonce:)`, `.chacha20(key:nonce:)` |
| HMAC keystream | `.hmacSHA256(key:salt:)`, `.hmacSHA384`, `.hmacSHA512` |
| HKDF + AEAD | `.hkdfAESGCM(...)`, `.hkdfChaChaPoly(...)` |
| ECIES | `.curve25519AESGCM(recipientPrivateKey:nonce:)`, `.p256AESGCM(...)` |

Pass `nil` for crypto key material to generate random values at compile time. Pass explicit `ObfuscatedKey`, `ObfuscatedNonce`, `ObfuscatedSalt`, or `ObfuscatedInfo` for reproducible output.

Methods chain left-to-right at encode time and reverse at decode time.

## Documentation

| Document | Contents |
|----------|----------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Mermaid diagrams and system data flow |
| [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md) | Full source reference — every module, type, and algorithm |
| [docs/RELEASE_NOTES/v1.0.0.md](docs/RELEASE_NOTES/v1.0.0.md) | Initial release notes |

## Testing

```bash
swift test
```

- `ObfuscatedCoreTests` — encode/decode round-trips and validation
- `ObfuscatedTests` — macro parsing and expansion

## Package layout

```
Sources/
  Obfuscated/          Public API (#Obfuscated)
  ObfuscatedCore/      Encode/decode pipeline and CryptoKit
  ObfuscatedMacros/    Compiler plugin (macro expansion)
Tests/
Demo/                  SwiftUI multiplatform demo
```

## License

MIT License. See [LICENSE](LICENSE).
