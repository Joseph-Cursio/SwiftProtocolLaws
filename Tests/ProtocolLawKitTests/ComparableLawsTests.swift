import Testing
import PropertyBased
@testable import ProtocolLawKit

@Suite struct ComparableLawsTests {

    @Test func intsPassAllLaws() async throws {
        let results = try await checkComparableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            budget: .sanity
        )
        for result in results {
            #expect(!result.isViolation,
                    "\(result.protocolLaw) should pass for Int — got: \(result.counterexample ?? "<no counter>")")
        }
    }

    @Test func stringsPassAllLaws() async throws {
        let results = try await checkComparableProtocolLaws(
            for: String.self,
            using: TestGen.smallString(),
            budget: .sanity
        )
        for result in results {
            #expect(!result.isViolation, "\(result.protocolLaw) should pass for String")
        }
    }

    @Test func defaultLawSelectionRunsInheritedEquatableSuiteFirst() async throws {
        let results = try await checkComparableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            budget: .sanity
        )
        let laws = results.map(\.protocolLaw)
        let firstComparableIndex = laws.firstIndex { $0.hasPrefix("Comparable.") }
        #expect(firstComparableIndex != nil)
        let inheritedLaws = laws[..<firstComparableIndex!]
        #expect(inheritedLaws.allSatisfy { $0.hasPrefix("Equatable.") })
        #expect(inheritedLaws.count == 4)
    }

    @Test func ownOnlySkipsInheritedEquatableSuite() async throws {
        let results = try await checkComparableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            budget: .sanity,
            laws: .ownOnly
        )
        #expect(results.allSatisfy { $0.protocolLaw.hasPrefix("Comparable.") })
        #expect(results.count == 4) // antisymmetry, transitivity, totality, operatorConsistency
    }

    @Test func tiersAreReportedAsDocumented() async throws {
        let results = try await checkComparableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            budget: .sanity,
            laws: .ownOnly
        )
        let tiersByLaw = Dictionary(uniqueKeysWithValues: results.map { ($0.protocolLaw, $0.tier) })
        #expect(tiersByLaw["Comparable.antisymmetry"] == .strict)
        #expect(tiersByLaw["Comparable.transitivity"] == .strict)
        #expect(tiersByLaw["Comparable.totality"] == .conventional)
        #expect(tiersByLaw["Comparable.operatorConsistency"] == .strict)
    }
}
