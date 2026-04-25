import Foundation
import Testing
import PropertyBased
@testable import ProtocolLawKit

private struct Invoice: Codable, Equatable, Sendable {
    let identifier: Int
    let amount: Int
    let memo: String
}

extension Gen where Value == Invoice {
    static func invoice() -> Generator<Invoice, some SendableSequenceType> {
        zip(
            Gen<Int>.int(in: 0...10_000),
            Gen<Int>.int(in: -1_000...1_000),
            Gen<Character>.letterOrNumber.string(of: 0...8)
        ).map { identifier, amount, memo in
            Invoice(identifier: identifier, amount: amount, memo: memo)
        }
    }
}

@Suite struct CodableLawsTests {

    @Test func intRoundTripsUnderStrict() async throws {
        let results = try await checkCodableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            config: CodableLawConfig(mode: .strict, codec: .json),
            options: LawCheckOptions(budget: .sanity)
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
            config: CodableLawConfig(mode: .strict, codec: .json),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(!results[0].isViolation, "Invoice should round-trip under JSON")
    }

    @Test func customStructRoundTripsUnderBinaryPlist() async throws {
        let results = try await checkCodableProtocolLaws(
            for: Invoice.self,
            using: Gen<Invoice>.invoice(),
            config: CodableLawConfig(mode: .strict, codec: .binaryPlist),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(!results[0].isViolation)
        #expect(results[0].protocolLaw == "Codable.roundTripFidelity[PropertyList(binary)]")
    }

    @Test func semanticEquivalenceModeUsesCallerPredicate() async throws {
        let results = try await checkCodableProtocolLaws(
            for: Invoice.self,
            using: Gen<Invoice>.invoice(),
            config: CodableLawConfig(mode: .semantic(equivalent: { _, _ in true })),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(!results[0].isViolation)
    }

    @Test func partialFieldsModeOnlyChecksListedFields() async throws {
        let results = try await checkCodableProtocolLaws(
            for: Invoice.self,
            using: Gen<Invoice>.invoice(),
            config: CodableLawConfig(mode: .partial(fields: [\Invoice.identifier, \Invoice.amount])),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(!results[0].isViolation)
    }
}
