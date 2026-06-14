import ObfuscatedCore
import ObfuscatedTestSupport
import Testing

@Suite("Custom obfuscation steps", .serialized)
struct CustomObfuscationStepTests {
    @Test func rot13RoundTrip() throws {
        registerRot13()
        let methods: [ObfuscationMethod] = [
            .custom(id: MyRot13Step.id, parameters: ObfuscationParameters(bytes: [13])),
        ]
        let payload = try ObfuscationPipeline.encode("Hello Secret", methods: methods)
        let decoded = try ObfuscationPipeline.decode(payload, methods: methods)
        #expect(decoded == "Hello Secret")
        #expect(payload.bytes != Array("Hello Secret".utf8))
    }

    @Test func rot13WithBuiltinPipelineRoundTrip() throws {
        registerRot13()
        let methods: [ObfuscationMethod] = [
            .custom(id: MyRot13Step.id, parameters: ObfuscationParameters(bytes: [13])),
            .xor(key: 0x5A),
            .base64,
        ]
        try assertRoundTrip("Mixed pipeline", methods: methods)
    }

    @Test func unknownCustomStepThrows() {
        ObfuscationStepRegistry.reset()
        let error = #expect(throws: ObfuscationError.self) {
            try ObfuscationPipeline.encode(
                "x",
                methods: [.custom(id: "missing", parameters: ObfuscationParameters(bytes: [1]))]
            )
        }
        #expect(error == .unknownCustomStep("missing"))
    }

    @Test func invalidRot13ParametersThrow() {
        registerRot13()
        let error = #expect(throws: ObfuscationError.self) {
            try ObfuscationPipeline.encode(
                "x",
                methods: [.custom(id: MyRot13Step.id, parameters: ObfuscationParameters(bytes: [0]))]
            )
        }
        guard case .decodingFailed(let message) = error else {
            Issue.record("Expected decodingFailed, got \(error)")
            return
        }
        #expect(message.contains("1…25"))
    }
}

private func registerRot13() {
    ObfuscationStepRegistry.reset()
    ObfuscationStepRegistry.register(MyRot13Step.self)
}

private func assertRoundTrip(_ string: String, methods: [ObfuscationMethod]) throws {
    let payload = try ObfuscationPipeline.encode(string, methods: methods)
    let decoded = try ObfuscationPipeline.decode(payload, methods: methods)
    #expect(decoded == string)
}
