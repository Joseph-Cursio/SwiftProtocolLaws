import Testing
import PropertyBased
@testable import ProtocolLawKit

struct IteratorProtocolLawsTests {

    @Test func arrayIteratorPassesAllLaws() async throws {
        let results = try await checkIteratorProtocolLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...8),
            options: LawCheckOptions(budget: .standard)
        )
        #expect(results.allSatisfy { $0.outcome == .passed })
        let names = results.map(\.protocolLaw)
        #expect(names.contains("IteratorProtocol.terminationStability"))
        #expect(names.contains("IteratorProtocol.singlePassYield"))
    }

    @Test func detectsResumingAfterNil() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkIteratorProtocolLaws(
                for: ResumingAfterNilSequence.self,
                using: Gen<ResumingAfterNilSequence>.resumingAfterNil(),
                options: LawCheckOptions(budget: .sanity, enforcement: .strict)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("IteratorProtocol.terminationStability"),
            "expected terminationStability in violation set; got: \(laws)"
        )
    }

    @Test func detectsInfiniteIterator() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkIteratorProtocolLaws(
                for: InfiniteCounterSequence.self,
                using: Gen<InfiniteCounterSequence>.infiniteCounter(),
                options: LawCheckOptions(budget: .sanity, enforcement: .strict)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("IteratorProtocol.singlePassYield"),
            "expected singlePassYield in violation set; got: \(laws)"
        )
    }

    @Test func conventionalLawsDoNotThrowByDefault() async throws {
        // Both laws are Conventional; default enforcement should report
        // violations as `.failed` results but not throw.
        let results = try await checkIteratorProtocolLaws(
            for: ResumingAfterNilSequence.self,
            using: Gen<ResumingAfterNilSequence>.resumingAfterNil(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.contains { $0.isViolation && $0.tier == .conventional })
    }
}
