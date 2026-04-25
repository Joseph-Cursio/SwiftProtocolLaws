import Testing
@testable import ProtocolLawKit

@Suite struct SeedTests {

    @Test func roundTripsThroughBase64() throws {
        let original = Seed(rawValue: (12_345, 67_890, 11_111, 22_222))
        let base64 = original.description
        let restored = try #require(Seed(base64: base64))
        #expect(restored == original)
    }

    @Test func returnsNilForInvalidBase64() {
        #expect(Seed(base64: "not-valid-base64!!!") == nil)
    }

    @Test func equalRawValuesProduceEqualSeeds() {
        let lhs = Seed(rawValue: (1, 2, 3, 4))
        let rhs = Seed(rawValue: (1, 2, 3, 4))
        #expect(lhs == rhs)
    }

    @Test func hashableTreatsEqualRawValuesAsOneEntry() {
        let dup1 = Seed(rawValue: (1, 2, 3, 4))
        let dup2 = Seed(rawValue: (1, 2, 3, 4))
        let other = Seed(rawValue: (5, 6, 7, 8))
        let set: Set<Seed> = [dup1, dup2, other]
        #expect(set.count == 2)
    }
}
