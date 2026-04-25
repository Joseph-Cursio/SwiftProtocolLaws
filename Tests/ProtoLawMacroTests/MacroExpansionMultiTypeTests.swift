import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import ProtoLawMacroImpl

@Suite struct MacroExpansionMultiTypeTests {

    @Test func expandsSetAlgebra() {
        let source = """
            struct Bag: SetAlgebra, Equatable {
                init() {}
                func contains(_: Int) -> Bool { false }
                func union(_: Bag) -> Bag { self }
                func intersection(_: Bag) -> Bag { self }
                func symmetricDifference(_: Bag) -> Bag { self }
                mutating func formUnion(_: Bag) {}
                mutating func formIntersection(_: Bag) {}
                mutating func formSymmetricDifference(_: Bag) {}
                mutating func insert(_: Int) -> (inserted: Bool, memberAfterInsert: Int) { (false, 0) }
                mutating func remove(_: Int) -> Int? { nil }
                mutating func update(with: Int) -> Int? { nil }
            }
            @ProtoLawSuite(types: [Bag.self])
            struct Tests {
                static let bagGen = Gen.bag()
            }
            """
        let expanded = expandedSetAlgebraExpected
        assertMacroExpansion(source, expandedSource: expanded, macros: testMacros)
    }

    @Test func expandsMultipleTypes() {
        assertMacroExpansion(
            """
            struct Foo: Equatable {
                let value: Int
            }
            struct Bar: Hashable {
                let other: Int
            }
            @ProtoLawSuite(types: [Foo.self, Bar.self])
            struct Tests {
                static let fooGen = Gen.foo()
                static let barGen = Gen.bar()
            }
            """,
            expandedSource: """
            struct Foo: Equatable {
                let value: Int
            }
            struct Bar: Hashable {
                let other: Int
            }
            struct Tests {
                static let fooGen = Gen.foo()
                static let barGen = Gen.bar()

                @Test func equatable_Foo() async throws {
                    try await checkEquatableProtocolLaws(
                        for: Foo.self,
                        using: Self.fooGen
                    )
                }

                @Test func hashable_Bar() async throws {
                    try await checkHashableProtocolLaws(
                        for: Bar.self,
                        using: Self.barGen
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - IteratorProtocol-only is silently skipped

    @Test func iteratorProtocolOnlyEmitsNothing() {
        // checkIteratorProtocolLaws is parameterized over a host Sequence
        // — calling it with a pure IteratorProtocol type wouldn't compile.
        // The macro skips this case rather than emit broken code.
        assertMacroExpansion(
            """
            struct Cursor: IteratorProtocol {
                mutating func next() -> Int? { nil }
            }
            @ProtoLawSuite(types: [Cursor.self])
            struct Tests {
                static let cursorGen = Gen.cursor()
            }
            """,
            expandedSource: """
            struct Cursor: IteratorProtocol {
                mutating func next() -> Int? { nil }
            }
            struct Tests {
                static let cursorGen = Gen.cursor()
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Conformance from extensions is aggregated

    @Test func aggregatesConformancesFromExtensions() {
        assertMacroExpansion(
            """
            struct Foo {
                let value: Int
            }
            extension Foo: Equatable {
                static func == (lhs: Foo, rhs: Foo) -> Bool { lhs.value == rhs.value }
            }
            extension Foo: Hashable {
                func hash(into hasher: inout Hasher) { hasher.combine(value) }
            }
            @ProtoLawSuite(types: [Foo.self])
            struct Tests {
                static let fooGen = Gen.foo()
            }
            """,
            expandedSource: """
            struct Foo {
                let value: Int
            }
            extension Foo: Equatable {
                static func == (lhs: Foo, rhs: Foo) -> Bool { lhs.value == rhs.value }
            }
            extension Foo: Hashable {
                func hash(into hasher: inout Hasher) { hasher.combine(value) }
            }
            struct Tests {
                static let fooGen = Gen.foo()

                @Test func hashable_Foo() async throws {
                    try await checkHashableProtocolLaws(
                        for: Foo.self,
                        using: Self.fooGen
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func generatorNameLowercasesFirstLetter() {
        // MyType → myTypeGen.
        assertMacroExpansion(
            """
            struct MyType: Equatable {
                let value: Int
            }
            @ProtoLawSuite(types: [MyType.self])
            struct Tests {
                static let myTypeGen = Gen.myType()
            }
            """,
            expandedSource: """
            struct MyType: Equatable {
                let value: Int
            }
            struct Tests {
                static let myTypeGen = Gen.myType()

                @Test func equatable_MyType() async throws {
                    try await checkEquatableProtocolLaws(
                        for: MyType.self,
                        using: Self.myTypeGen
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    /// Hoisted out of `expandsSetAlgebra` to keep the test body under
    /// SwiftLint's function-body-length limit. The Bag-conformance
    /// boilerplate dominates the expected source either way.
    private var expandedSetAlgebraExpected: String {
        """
        struct Bag: SetAlgebra, Equatable {
            init() {}
            func contains(_: Int) -> Bool { false }
            func union(_: Bag) -> Bag { self }
            func intersection(_: Bag) -> Bag { self }
            func symmetricDifference(_: Bag) -> Bag { self }
            mutating func formUnion(_: Bag) {}
            mutating func formIntersection(_: Bag) {}
            mutating func formSymmetricDifference(_: Bag) {}
            mutating func insert(_: Int) -> (inserted: Bool, memberAfterInsert: Int) { (false, 0) }
            mutating func remove(_: Int) -> Int? { nil }
            mutating func update(with: Int) -> Int? { nil }
        }
        struct Tests {
            static let bagGen = Gen.bag()

            @Test func equatable_Bag() async throws {
                try await checkEquatableProtocolLaws(
                    for: Bag.self,
                    using: Self.bagGen
                )
            }

            @Test func setAlgebra_Bag() async throws {
                try await checkSetAlgebraProtocolLaws(
                    for: Bag.self,
                    using: Self.bagGen
                )
            }
        }
        """
    }
}
