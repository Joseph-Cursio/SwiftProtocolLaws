import Testing
import PropertyBased
import PropertyLawKit

/// Pass 2 validation — v1.5 StringProtocol cluster against stdlib `String`
/// and `Substring`.
///
/// String and Substring are the two stdlib StringProtocol conformers. The
/// kit's eight Strict-tier StringProtocol laws (own-only) plus the
/// transitively-inherited BidirectionalCollection / Collection / Sequence /
/// IteratorProtocol laws all run end-to-end against Apple's reference
/// implementations at `.standard` budget.
///
/// Generators sample short ASCII-letter strings (length 0...8) — broad
/// enough to exercise the boundary cases (empty string, single char, ASCII
/// case folding) without slowing the sub-package's run time.
struct StdlibStringPropertyLawsTests {

    @Test func stringPassesStringPropertyLaws() async throws {
        try await checkStringProtocolPropertyLaws(
            for: String.self,
            using: Gen<Character>.letterOrNumber.string(of: 0...8),
            options: LawCheckOptions(budget: .standard)
        )
    }

    @Test func substringPassesStringPropertyLaws() async throws {
        try await checkStringProtocolPropertyLaws(
            for: Substring.self,
            using: Gen<Character>.letterOrNumber.string(of: 0...8).map { Substring($0) },
            options: LawCheckOptions(budget: .standard)
        )
    }
}
