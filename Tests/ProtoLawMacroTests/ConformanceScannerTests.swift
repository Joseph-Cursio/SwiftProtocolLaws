import SwiftSyntax
import SwiftParser
import Testing
@testable import ProtoLawMacroImpl

@Suite struct ConformanceScannerTests {

    private func parse(_ source: String) -> SourceFileSyntax {
        Parser.parse(source: source)
    }

    // MARK: - KnownProtocol mapping

    @Test func knownProtocolFromExactNames() {
        #expect(KnownProtocol.from(typeName: "Equatable") == .equatable)
        #expect(KnownProtocol.from(typeName: "Hashable") == .hashable)
        #expect(KnownProtocol.from(typeName: "Comparable") == .comparable)
        #expect(KnownProtocol.from(typeName: "Codable") == .codable)
        #expect(KnownProtocol.from(typeName: "IteratorProtocol") == .iteratorProtocol)
        #expect(KnownProtocol.from(typeName: "Sequence") == .sequence)
        #expect(KnownProtocol.from(typeName: "Collection") == .collection)
        #expect(KnownProtocol.from(typeName: "SetAlgebra") == .setAlgebra)
        #expect(KnownProtocol.from(typeName: "NotAStdlibProtocol") == nil)
    }

    @Test func encodableDecodablePairResolvesToCodable() {
        let set = KnownProtocol.set(from: ["Encodable", "Decodable"])
        #expect(set == [.codable])
    }

    @Test func encodableAloneDoesNotResolveToCodable() {
        // Codable requires both halves; Encodable alone is not enough to
        // claim a Codable conformance.
        let set = KnownProtocol.set(from: ["Encodable"])
        #expect(set == [])
    }

    @Test func sendableAndOtherUnknownsAreIgnored() {
        let set = KnownProtocol.set(from: ["Sendable", "CustomStringConvertible", "Equatable"])
        #expect(set == [.equatable])
    }

    // MARK: - Most-specific subsumption (PRD §4.3)

    @Test func hashableSubsumesEquatable() {
        let result = KnownProtocol.mostSpecific(in: [.equatable, .hashable])
        #expect(result == [.hashable])
    }

    @Test func comparableSubsumesEquatable() {
        let result = KnownProtocol.mostSpecific(in: [.equatable, .comparable])
        #expect(result == [.comparable])
    }

    @Test func collectionSubsumesSequenceAndIterator() {
        let result = KnownProtocol.mostSpecific(in: [.iteratorProtocol, .sequence, .collection])
        #expect(result == [.collection])
    }

    @Test func sequenceSubsumesIteratorButNotCollection() {
        let result = KnownProtocol.mostSpecific(in: [.iteratorProtocol, .sequence])
        #expect(result == [.sequence])
    }

    @Test func independentProtocolsBothSurvive() {
        // Comparable and Codable cover different laws; both should emit.
        let result = KnownProtocol.mostSpecific(in: [.comparable, .codable])
        #expect(result == [.comparable, .codable])
    }

    @Test func hashableAndComparableBothSurvive() {
        // Both subsume Equatable, but neither subsumes the other — both
        // calls should be emitted (the §4.3 plugin example).
        let result = KnownProtocol.mostSpecific(in: [.equatable, .hashable, .comparable])
        #expect(result == [.hashable, .comparable])
    }

    // MARK: - ConformanceScanner — same-file detection

    @Test func detectsStructConformances() {
        let file = parse("""
            struct Foo: Equatable, Hashable {
                let value: Int
            }
            """)
        let result = ConformanceScanner.conformances(of: "Foo", in: file)
        #expect(result == [.hashable])  // most-specific dedupe drops Equatable
    }

    @Test func detectsEnumConformances() {
        let file = parse("""
            enum Direction: String, Codable, CaseIterable {
                case north, south, east, west
            }
            """)
        let result = ConformanceScanner.conformances(of: "Direction", in: file)
        #expect(result == [.codable])
    }

    @Test func detectsClassConformances() {
        let file = parse("""
            final class Cache: Sequence {
                func makeIterator() -> AnyIterator<Int> { AnyIterator { nil } }
            }
            """)
        let result = ConformanceScanner.conformances(of: "Cache", in: file)
        #expect(result == [.sequence])
    }

    @Test func detectsActorConformances() {
        let file = parse("""
            actor Counter: Equatable {
                var value: Int = 0
                static func == (lhs: Counter, rhs: Counter) -> Bool { false }
            }
            """)
        let result = ConformanceScanner.conformances(of: "Counter", in: file)
        #expect(result == [.equatable])
    }

    @Test func aggregatesConformancesFromExtensions() {
        // Primary decl declares Equatable; extension adds Hashable.
        let file = parse("""
            struct Foo: Equatable {
                let value: Int
            }
            extension Foo: Hashable {
                func hash(into hasher: inout Hasher) { hasher.combine(value) }
            }
            """)
        let result = ConformanceScanner.conformances(of: "Foo", in: file)
        // Hashable subsumes Equatable.
        #expect(result == [.hashable])
    }

    @Test func conditionalConformanceExtensionIsSkipped() {
        // `extension Container: Equatable where T: Equatable` is conditional
        // (PRD §4.4) — M1 skips these to avoid claiming an unconditional
        // conformance. The primary decl's Equatable still surfaces.
        let file = parse("""
            struct Container<T> {
                let item: T
            }
            extension Container: Equatable where T: Equatable {
                static func == (lhs: Container, rhs: Container) -> Bool { false }
            }
            """)
        let result = ConformanceScanner.conformances(of: "Container", in: file)
        // Container's primary decl has no inheritance clause, and the
        // conditional extension is skipped, so no recognized conformance.
        #expect(result == [])
    }

    @Test func unconditionalExtensionConformanceIsAggregated() {
        let file = parse("""
            struct Foo {
                let value: Int
            }
            extension Foo: Equatable {
                static func == (lhs: Foo, rhs: Foo) -> Bool { lhs.value == rhs.value }
            }
            """)
        let result = ConformanceScanner.conformances(of: "Foo", in: file)
        #expect(result == [.equatable])
    }

    @Test func returnsNilWhenTypeNotInFile() {
        let file = parse("""
            struct Bar {}
            """)
        let result = ConformanceScanner.conformances(of: "Foo", in: file)
        #expect(result == nil)
    }

    @Test func returnsEmptySetForRecognizedTypeWithNoStdlibConformance() {
        // Foo exists, but its only conformance is a custom protocol.
        let file = parse("""
            struct Foo: MyCustomProtocol {
                let value: Int
            }
            """)
        let result = ConformanceScanner.conformances(of: "Foo", in: file)
        // Empty set, NOT nil — distinguishes "found, no recognized
        // conformance" from "not in file at all" so the macro can emit
        // different diagnostics.
        #expect(result == [])
    }
}
