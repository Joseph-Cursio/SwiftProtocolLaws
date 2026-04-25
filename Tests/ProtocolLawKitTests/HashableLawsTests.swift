import Testing
import PropertyBased
@testable import ProtocolLawKit

@Suite struct HashableLawsTests {

    @Test func intsPassAllLaws() async throws {
        let results = try await checkHashableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            budget: .sanity
        )
        for result in results {
            #expect(!result.isViolation, "\(result.protocolLaw) failed for Int: \(result.counterexample ?? "<no counter>")")
        }
    }

    @Test func customStructPassesAllLaws() async throws {
        let results = try await checkHashableProtocolLaws(
            for: Coordinate.self,
            using: Gen<Coordinate>.coordinate(),
            budget: .sanity
        )
        for result in results {
            #expect(!result.isViolation, "\(result.protocolLaw) failed for Coordinate: \(result.counterexample ?? "<no counter>")")
        }
    }

    @Test func defaultLawSelectionRunsInheritedEquatableSuiteFirst() async throws {
        let results = try await checkHashableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            budget: .sanity
        )
        let laws = results.map(\.protocolLaw)
        // Equatable's four laws appear before any Hashable law
        let firstHashableIndex = laws.firstIndex { $0.hasPrefix("Hashable.") }
        #expect(firstHashableIndex != nil)
        let equatableLaws = laws[..<firstHashableIndex!]
        #expect(equatableLaws.allSatisfy { $0.hasPrefix("Equatable.") })
        #expect(equatableLaws.count == 4)
    }

    @Test func ownOnlySkipsInheritedEquatableSuite() async throws {
        let results = try await checkHashableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            budget: .sanity,
            laws: .ownOnly
        )
        #expect(results.allSatisfy { $0.protocolLaw.hasPrefix("Hashable.") })
        #expect(results.count == 3) // equalityConsistency, stabilityWithinProcess, distribution
    }

    @Test func tiersAreReportedAsDocumented() async throws {
        let results = try await checkHashableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            budget: .sanity,
            laws: .ownOnly
        )
        let tiersByLaw = Dictionary(uniqueKeysWithValues: results.map { ($0.protocolLaw, $0.tier) })
        #expect(tiersByLaw["Hashable.equalityConsistency"] == .strict)
        #expect(tiersByLaw["Hashable.stabilityWithinProcess"] == .conventional)
        #expect(tiersByLaw["Hashable.distribution"] == .heuristic)
    }
}
