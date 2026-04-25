import Foundation
import Testing
import PropertyBased
@testable import ProtocolLawKit

private struct Invoice: Codable, Equatable, Sendable {
    let id: Int
    let amount: Int
    let memo: String
}

extension Gen where Value == Invoice {
    static func invoice() -> Generator<Invoice, some SendableSequenceType> {
        zip(
            Gen<Int>.int(in: 0...10_000),
            Gen<Int>.int(in: -1_000...1_000),
            Gen<Character>.letterOrNumber.string(of: 0...8)
        ).map { id, amount, memo in
            Invoice(id: id, amount: amount, memo: memo)
        }
    }
}

@Suite struct CodableLawsTests {

    @Test func intRoundTripsUnderStrict() async throws {
        let results = try await checkCodableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            mode: .strict,
            codec: .json,
            budget: .sanity
        )
        #expect(results.count == 1)
        #expect(!results[0].isViolation)
        #expect(results[0].tier == .conventional)
        #expect(results[0].protocolLaw == "Codable.roundTripFidelity[JSON]")
    }

    @Test func customStructRoundTripsUnderStrictJSON() async throws {
        let results = try await checkCodableProtocolLaws(
            for: Invoice.self,
            using: Gen<Invoice>.invoice(),
            mode: .strict,
            codec: .json,
            budget: .sanity
        )
        #expect(!results[0].isViolation,
                "Invoice should round-trip under JSON: \(results[0].counterexample ?? "<no counter>")")
    }

    @Test func customStructRoundTripsUnderBinaryPlist() async throws {
        let results = try await checkCodableProtocolLaws(
            for: Invoice.self,
            using: Gen<Invoice>.invoice(),
            mode: .strict,
            codec: .binaryPlist,
            budget: .sanity
        )
        #expect(!results[0].isViolation)
        #expect(results[0].protocolLaw == "Codable.roundTripFidelity[PropertyList(binary)]")
    }

    @Test func semanticEquivalenceModeUsesCallerPredicate() async throws {
        // Permissive predicate that always returns true — should pass even
        // for types whose strict round-trip would normally pass too.
        let results = try await checkCodableProtocolLaws(
            for: Invoice.self,
            using: Gen<Invoice>.invoice(),
            mode: .semantic(equivalent: { _, _ in true }),
            codec: .json,
            budget: .sanity
        )
        #expect(!results[0].isViolation)
    }

    @Test func partialFieldsModeOnlyChecksListedFields() async throws {
        let results = try await checkCodableProtocolLaws(
            for: Invoice.self,
            using: Gen<Invoice>.invoice(),
            mode: .partial(fields: [\Invoice.id, \Invoice.amount]),
            codec: .json,
            budget: .sanity
        )
        #expect(!results[0].isViolation)
    }
}
