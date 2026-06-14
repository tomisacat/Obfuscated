import Foundation
import ObfuscatedCore
import Testing

private func assertRoundTrip<T: ObfuscatedValue & Equatable>(
    _ value: T,
    methods: [ObfuscationMethod]
) throws {
    let payload = try ObfuscationPipeline.encode(value, methods: methods)
    let decoded = try ObfuscationPipeline.decode(payload, methods: methods, as: T.self)
    #expect(decoded == value)
}

@Suite("Obfuscated value types")
struct ObfuscatedValueTests {
    @Test func intRoundTrip() throws {
        try assertRoundTrip(42_001, methods: [.xor(key: 0x5A)])
    }

    @Test func negativeIntRoundTrip() throws {
        try assertRoundTrip(-1, methods: [.xor(key: 0x11)])
    }

    @Test func boolRoundTrip() throws {
        try assertRoundTrip(true, methods: [.xor(key: 1)])
        try assertRoundTrip(false, methods: [.xor(key: 1)])
    }

    @Test func dataRoundTrip() throws {
        try assertRoundTrip(Data([0xDE, 0xAD, 0xBE, 0xEF]), methods: [.xor(key: 0x33)])
    }

    @Test func intBackedEnumRoundTrip() throws {
        enum Color: Int {
            case red = 1
            case blue = 2
        }
        let methods: [ObfuscationMethod] = [.xor(key: 0x7)]
        let payload = try ObfuscationPipeline.encode(Color.red, methods: methods)
        let decoded = try ObfuscationPipeline.decode(payload, methods: methods, as: Color.self)
        #expect(decoded == .red)
    }

    @Test func stringBackedEnumRoundTrip() throws {
        enum Role: String {
            case admin
            case guest
        }
        let methods: [ObfuscationMethod] = [.xor(key: 0x2A)]
        let payload = try ObfuscationPipeline.encode(Role.admin, methods: methods)
        let decoded = try ObfuscationPipeline.decode(payload, methods: methods, as: Role.self)
        #expect(decoded == .admin)
    }

    @Test func caseIterableEnumDecode() throws {
        enum Environment: CaseIterable, Sendable {
            case production
            case staging
        }

        let methods: [ObfuscationMethod] = [.xor(key: 0x3C)]
        let payload = try ObfuscationPipeline.encode("production", methods: methods)
        let decoded = try ObfuscationPipeline.decode(payload, methods: methods, as: String.self)
        #expect(decoded == "production")
        #expect(try ObfuscatedEnumSupport.caseNamed("production", in: Environment.self) == .production)
    }
}
