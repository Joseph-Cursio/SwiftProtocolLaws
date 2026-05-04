import Testing
import PropertyBased
@testable import PropertyLawKit

/// PRD §8 framework self-test gate — v1.4 numeric cluster (M2 share).
struct PlantedBugIntegerDetectionTests {

    // MARK: - BinaryInteger Strict-tier planted bug

    @Test func detectsBrokenBitwiseNegation() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkBinaryIntegerPropertyLaws(
                for: BrokenBitwiseNegation.self,
                using: Gen<BrokenBitwiseNegation>.brokenBitwiseNegation(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("BinaryInteger.bitwiseDoubleNegation"),
            "expected bitwiseDoubleNegation in violation set; got: \(laws)"
        )
    }

    // MARK: - SignedInteger Strict-tier planted bug

    @Test func detectsLyingSignum() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSignedIntegerPropertyLaws(
                for: LyingSignum.self,
                using: Gen<LyingSignum>.lyingSignum(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("SignedInteger.signednessConsistency"),
            "expected signednessConsistency in violation set; got: \(laws)"
        )
    }

    // MARK: - UnsignedInteger Strict-tier planted bug

    @Test func detectsLyingMagnitude() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkUnsignedIntegerPropertyLaws(
                for: LyingMagnitude.self,
                using: Gen<LyingMagnitude>.lyingMagnitude(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("UnsignedInteger.magnitudeIsSelf"),
            "expected magnitudeIsSelf in violation set; got: \(laws)"
        )
    }

    // MARK: - FixedWidthInteger Strict-tier planted bug

    @Test func detectsBrokenByteSwapped() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkFixedWidthIntegerPropertyLaws(
                for: BrokenByteSwapped.self,
                using: Gen<BrokenByteSwapped>.brokenByteSwapped(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("FixedWidthInteger.byteSwappedInvolution"),
            "expected byteSwappedInvolution in violation set; got: \(laws)"
        )
    }
}
