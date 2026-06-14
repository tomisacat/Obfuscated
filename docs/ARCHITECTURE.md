# Obfuscated — Architecture

← [Back to README](../README.md)

For the full source reference (every type, file, and algorithm), see [DOCUMENTATION.md](DOCUMENTATION.md).

## Module structure

```mermaid
flowchart TB
    subgraph Consumer["Consumer app"]
        SRC["Source code\n#Obfuscated(\"secret\", methods: [...])"]
    end

    subgraph Product["Product: Obfuscated"]
        API["Obfuscated.swift\n• #Obfuscated → ObfuscatedMacros\n• typealiases"]
    end

    subgraph MacroSupport["ObfuscatedMacroSupport (library)"]
        PARSER["MacroSyntaxParser"]
        BUILDER["MacroExpansionBuilder"]
        EXPR["ObfuscatedMacro"]
        CONFIG["ObfuscationMacroConfiguration"]
    end

    subgraph DefaultPlugin["ObfuscatedMacros (default plugin)"]
        PLUGIN["ObfuscatedPlugin\n(built-in methods only)"]
    end

    subgraph Core["ObfuscatedCore"]
        PIPE["ObfuscationPipeline"]
        RUNTIME["ObfuscatedRuntime._decode"]
        METHODS["ObfuscationMethod\nObfuscationStep / Registry"]
        MAT["CryptoMaterial\nCryptoEntry + CustomMaterialEntry"]
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
    PLUGIN --> CONFIG
    PLUGIN --> EXPR
    EXPR --> PARSER --> BUILDER
    BUILDER --> PIPE
    PIPE --> BIT & B64 & CRYPTO & METHODS
    CRYPTO --> CK
    BUILDER --> RUNTIME
    API --> RUNTIME
    RUNTIME --> PIPE
    PIPE --> METHODS & MAT
    CONFIG --> METHODS
```

**Default path:** `import Obfuscated` → `#Obfuscated` expands via `ObfuscatedMacros` (no custom steps registered).

**Custom steps path:** a user- or demo-owned macro plugin target links `ObfuscatedMacroSupport`, registers `ObfuscationStep` types in `ObfuscationMacroConfiguration.configure`, and exposes `#Obfuscated` via `#externalMacro(module: "YourMacros", ...)`. See [CUSTOM_OBFUSCATION_STEPS.md](CUSTOM_OBFUSCATION_STEPS.md) and the demo package below.

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
        R1b["Pop custom entries\n(ObfuscationStep.decode)"]
        R2["base64 decode"]
        R3["bitOr / bitShift / xor"]
        R1 --> R1b --> R2 --> R3
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
        E1b["custom (ObfuscationStep.encode)"]
        E2["base64"]
        E3["CryptoObfuscator.encrypt"]
        E1 --> E1b --> E2 --> E3
    end

    ENC --> OUT["EncodedPayload"]

    subgraph OUT["EncodedPayload"]
        BYTES["bytes: [UInt8]"]
        MATBOX["material: CryptoMaterial"]
    end

    subgraph MATBOX["CryptoMaterial (per step)"]
        ENTRY["CryptoEntry\n• algorithm\n• payload (ciphertext)\n• masked keys / nonces / pub keys"]
        CUSTOM["CustomMaterialEntry\n• id\n• step payload"]
    end

    OUT --> DEC

    subgraph DEC["decode (reversed)"]
        direction RL
        D3["CryptoObfuscator.decrypt"]
        D3b["ObfuscationStep.decode"]
        D2["base64 decode"]
        D1["xor / bitShift / bitOr"]
        D3 --> D3b --> D2 --> D1
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

## Custom obfuscation (optional)

```mermaid
flowchart TB
    subgraph AppSteps["Your app / demo steps target"]
        STEP["ObfuscationStep\n(e.g. DemoRot13Step)"]
    end

    subgraph UserPlugin["User-owned macro plugin"]
        UINIT["ObfuscationMacroConfiguration.configure {\n  ObfuscationStepRegistry.register(...) }"]
        UPLUGIN["YourMacros.ObfuscatedPlugin"]
        UMACRO["ObfuscatedMacro\n(from ObfuscatedMacroSupport)"]
    end

    subgraph Registry["ObfuscationStepRegistry"]
        REG["id → step type"]
    end

    subgraph Pipeline["ObfuscationPipeline"]
        ENC[".custom(id:parameters:)\n→ step.encode"]
        DEC["pop custom entry\n→ step.decode"]
    end

    STEP --> UINIT
    UINIT --> REG
    UPLUGIN --> UMACRO
    UMACRO --> ENC
    ENC --> REG
    DEC --> REG
```

Custom steps use ``ObfuscationMethod/custom(id:parameters:)`` in macro source. The plugin must register conforming types before expansion so compile-time `encode` can dispatch to them. Runtime `decode` uses the same registry (the demo app also registers at launch so decode works in the built binary).

## Demo layout

```mermaid
flowchart LR
    subgraph DemoApp["Demo/ObfuscatedDemo (Xcode)"]
        APP["ObfuscatedDemoApp\nContentView\nDemoSecrets"]
    end

    subgraph DemoSupport["Demo/ObfuscatedDemoSupport (local SPM)"]
        KIT["ObfuscatedDemoKit\n#Obfuscated → ObfuscatedDemoMacros"]
        DMAC["ObfuscatedDemoMacros\nregisters DemoRot13Step"]
        DSTEPS["ObfuscatedDemoSteps\nDemoRot13Step"]
    end

    subgraph RootPkg["Root package: Obfuscated"]
        CORE["ObfuscatedCore"]
        MSUP["ObfuscatedMacroSupport"]
    end

    APP --> KIT
    KIT --> DMAC & DSTEPS
    DMAC --> MSUP & DSTEPS
    DSTEPS --> CORE
    KIT --> CORE
```

The demo support package is **not** part of the published root package — it exists only to show how to wire a custom macro plugin for the sample app.

## Test targets

```mermaid
flowchart LR
    CORE_T["ObfuscatedCoreTests\nround-trip pipeline\ncustom step tests"]
    MACRO_T["ObfuscatedTests\nmacro parse + expansion\nsnapshot / smoke tests"]
    DEMO["ObfuscatedDemo\nSwiftUI catalog"]
    DEMO_SUP["ObfuscatedDemoSupport\nlocal package build"]

    CORE_T --> Core["ObfuscatedCore"]
    MACRO_T --> MacroSupport["ObfuscatedMacroSupport"]
    MACRO_T --> Core
    DEMO --> DemoKit["ObfuscatedDemoKit"]
    DEMO_SUP --> DemoKit
    DemoKit --> Core
    DemoKit --> MacroSupport
```

## Summary

| Layer | Role |
|--------|------|
| **Obfuscated** | Public API surface; re-exports core types; default `#Obfuscated` → `ObfuscatedMacros` |
| **ObfuscatedMacroSupport** | Shared macro parser, builder, `ObfuscatedMacro`, and registration hook |
| **ObfuscatedMacros** | Default compiler plugin (built-in methods only) |
| **ObfuscationStep** | Optional user-defined transforms via `.custom(id:parameters:)` |
| **ObfuscationPipeline** | Shared encode/decode engine for macro + runtime |
| **CryptoObfuscator** | CryptoKit-backed steps; keys stored masked in `CryptoMaterial` |
| **ObfuscatedRuntime** | Thin runtime entry point embedded by macro expansions |
| **ObfuscatedDemoSupport** | Demo-only local package showing custom plugin wiring |

**Design principle:** obfuscation happens at **compile time**; runtime only **reverses** the embedded byte payload to return an ordinary `String`.
