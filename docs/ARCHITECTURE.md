# Obfuscated — Architecture

← [Back to README](../README.md)

For the full source reference (every type, file, and algorithm), see [DOCUMENTATION.md](DOCUMENTATION.md).

## Module structure

```mermaid
flowchart TB
    subgraph Consumer["Consumer app (e.g. Demo)"]
        SRC["Source code\n#Obfuscated(\"secret\", methods: [...])\nor #Obfuscated(\"Bearer \\(\"token\")\", ...)"]
    end

    subgraph Product["Product: Obfuscated"]
        API["Obfuscated.swift\n• #Obfuscated\n• typealiases"]
    end

    subgraph Macros["ObfuscatedMacros (compiler plugin)"]
        PLUGIN["ObfuscatedPlugin"]
        PARSER["MacroSyntaxParser"]
        BUILDER["MacroExpansionBuilder"]
        EXPR["ObfuscatedMacro"]
    end

    subgraph Core["ObfuscatedCore"]
        PIPE["ObfuscationPipeline"]
        RUNTIME["ObfuscatedRuntime._decode"]
        METHODS["ObfuscationMethod\nObfuscatedKey / Nonce / Salt / Info"]
        MAT["CryptoMaterial\nCryptoEntry\nEncodedPayload"]
        BIT["BitwiseObfuscator"]
        B64["Base64Obfuscator"]
        CRYPTO["CryptoObfuscator\n(CryptoKit)"]
    end

    subgraph External["External"]
        SWIFT["Swift compiler"]
        CK["CryptoKit / Security"]
    end

    SRC --> API
    API --> SWIFT
    SWIFT --> PLUGIN
    PLUGIN --> EXPR
    EXPR --> PARSER --> BUILDER
    BUILDER --> PIPE
    PIPE --> BIT & B64 & CRYPTO
    CRYPTO --> CK
    BUILDER --> RUNTIME
    API --> RUNTIME
    RUNTIME --> PIPE
    PIPE --> METHODS & MAT
```

## Compile-time expansion

```mermaid
sequenceDiagram
    participant Dev as Developer source
    participant Compiler as Swift compiler
    participant Macro as ObfuscatedMacro
    participant Parser as MacroSyntaxParser
    participant Pipeline as ObfuscationPipeline
    participant Builder as MacroExpansionBuilder
    participant Binary as Compiled binary

    Dev->>Compiler: #Obfuscated("Bearer \("apiKey")", methods: [.xor(0x5A), .aesGCM(...)])
    Compiler->>Macro: expand macro (plugin)
    Macro->>Parser: fold static literal + parse methods array
    Note over Parser: "Bearer " + "apiKey" → "Bearer apiKey"
    Parser-->>Macro: folded String + [ObfuscationMethod]
    Macro->>Pipeline: encode(foldedString, methods)
    Note over Pipeline: Runs obfuscation chain at compile time
    Pipeline-->>Macro: EncodedPayload(bytes, material)
    Macro->>Builder: decodeExpression(payload, methods)
    Builder-->>Compiler: ObfuscatedRuntime._decode(bytes: [...], methods: [...], material: ...)
    Compiler->>Binary: Embed byte arrays + crypto material<br/>Plaintext literal not stored
```

**What lands in the binary:** obfuscated `[UInt8]` payload, method descriptors, and masked `CryptoMaterial` — not the original string.

## Runtime decode

```mermaid
flowchart LR
    subgraph App["App runtime"]
        CALL["ObfuscatedRuntime._decode(\n  bytes, methods, material)"]
        DEC["ObfuscationPipeline.decode"]
        STR["String"]
    end

    CALL --> DEC
    DEC --> STR

    subgraph Reverse["Reverse method chain"]
        direction TB
        R1["Pop crypto entries\n(CryptoObfuscator.decrypt)"]
        R2["base64 decode"]
        R3["bitOr / bitShift / xor"]
        R1 --> R2 --> R3
    end

    DEC --> Reverse
```

The app uses a normal `String`. Decode is hidden inside the macro expansion; callers never call `_decode` themselves.

## Obfuscation pipeline

```mermaid
flowchart TB
    IN["UTF-8 plaintext"] --> ENC

    subgraph ENC["encode (forward)"]
        direction LR
        E1["xor / bitShift / bitOr"]
        E2["base64"]
        E3["CryptoObfuscator.encrypt"]
        E1 --> E2 --> E3
    end

    ENC --> OUT["EncodedPayload"]

    subgraph OUT["EncodedPayload"]
        BYTES["bytes: [UInt8]"]
        MATBOX["material: CryptoMaterial"]
    end

    subgraph MATBOX["CryptoMaterial (per crypto step)"]
        ENTRY["CryptoEntry\n• algorithm\n• payload (ciphertext)\n• masked keys / nonces / pub keys"]
    end

    OUT --> DEC

    subgraph DEC["decode (reversed)"]
        direction RL
        D3["CryptoObfuscator.decrypt"]
        D2["base64 decode"]
        D1["xor / bitShift / bitOr"]
        D3 --> D2 --> D1
    end

    DEC --> UTF["UTF-8 String"]
```

## Crypto layer detail

```mermaid
flowchart TB
    subgraph Methods["ObfuscationMethod (crypto)"]
        AEAD["aesGCM / chaChaPoly / chacha20"]
        HMAC["hmacSHA256 / 384 / 512"]
        HKDF["hkdfAESGCM / hkdfChaChaPoly"]
        ECIES["curve25519AESGCM / p256AESGCM"]
    end

    subgraph CryptoObfuscator["CryptoObfuscator"]
        SEAL["AEAD seal / HMAC keystream XOR"]
        HKDFD["HKDF derive + AEAD"]
        EC["ECIES: ephemeral key agreement\n→ shared secret → AES-GCM"]
        MASK["MaskedStorage\nmask keys with random byte"]
    end

    subgraph Store["Stored in expansion"]
        CM["CryptoMaterial.entries[]"]
    end

    Methods --> CryptoObfuscator
    SEAL & HKDFD & EC --> MASK --> CM
    CK["CryptoKit"] --> CryptoObfuscator
```

## Test targets

```mermaid
flowchart LR
    CORE_T["ObfuscatedCoreTests\nround-trip pipeline\ncrypto edge cases"]
    MACRO_T["ObfuscatedTests\nmacro parse + expansion\nsnapshot / smoke tests"]
    DEMO["ObfuscatedDemo\nSwiftUI catalog"]

    CORE_T --> Core["ObfuscatedCore"]
    MACRO_T --> Macros["ObfuscatedMacros"]
    MACRO_T --> Core
    DEMO --> Product["Obfuscated"]
```

## Summary

| Layer | Role |
|--------|------|
| **Obfuscated** | Public API surface; re-exports core types |
| **ObfuscatedMacros** | Compile-time plugin: parse → encode → emit `_decode(...)` |
| **ObfuscationPipeline** | Shared encode/decode engine for macro + runtime |
| **CryptoObfuscator** | CryptoKit-backed steps; keys stored masked in `CryptoMaterial` |
| **ObfuscatedRuntime** | Thin runtime entry point embedded by macro expansions |

**Design principle:** obfuscation happens at **compile time**; runtime only **reverses** the embedded byte payload to return an ordinary `String`.
