import Testing
@testable import ProtoLawDiscoveryTool
@testable import ProtoLawCore

@Suite struct EmitterGoldenTests {

    /// Convenience builder. Most existing emitter tests want `.userGen`
    /// (the M1 default — emitter spells `<TypeName>.gen()`); the new M3
    /// tests at the bottom override the strategy explicitly.
    private func entry(
        _ typeName: String,
        conformances: Set<KnownProtocol>,
        provenances: [ConformanceMap.Provenance] = [],
        strategy: DerivationStrategy = .userGen
    ) -> ConformanceMap.Entry {
        ConformanceMap.Entry(
            typeName: typeName,
            conformances: conformances,
            provenances: provenances.isEmpty
                ? [ConformanceMap.Provenance(filePath: "/p/\(typeName).swift", line: 1, kind: .primary)]
                : provenances,
            derivationStrategy: strategy
        )
    }

    // MARK: - Single-type happy paths

    @Test func emitsEquatableSuite() {
        let map = ConformanceMap(entries: [entry("Foo", conformances: [.equatable])], parseFailures: [])
        let output = GeneratedFileEmitter.emit(target: "MyModule", map: map)
        #expect(output.contains("import Testing"))
        #expect(output.contains("import ProtocolLawKit"))
        #expect(output.contains("// Target: MyModule"))
        #expect(output.contains("// Types detected: 1"))
        #expect(output.contains("@Suite struct FooProtocolLawTests {"))
        #expect(output.contains("@Test func equatable_Foo() async throws {"))
        #expect(output.contains("try await checkEquatableProtocolLaws("))
        #expect(output.contains("for: Foo.self,"))
        #expect(output.contains("using: Foo.gen()"))
    }

    @Test func emitsHashableSubsumesEquatable() {
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(entries: [entry("Foo", conformances: [.hashable])], parseFailures: [])
        )
        #expect(output.contains("checkHashableProtocolLaws"))
        // Equatable check NOT emitted — subsumed.
        #expect(!output.contains("checkEquatableProtocolLaws"))
    }

    @Test func emitsCodableAndEquatable() {
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(
                entries: [entry("Record", conformances: [.equatable, .codable])],
                parseFailures: []
            )
        )
        #expect(output.contains("@Test func equatable_Record() async throws {"))
        #expect(output.contains("@Test func codable_Record() async throws {"))
        let equatableRange = output.range(of: "equatable_Record")!
        let codableRange = output.range(of: "codable_Record")!
        #expect(equatableRange.lowerBound < codableRange.lowerBound)
    }

    // MARK: - Provenance comments

    @Test func provenanceCommentListsAllSources() {
        let provenances = [
            ConformanceMap.Provenance(
                filePath: "Sources/MyModule/Foo.swift",
                line: 1,
                kind: .primary
            ),
            ConformanceMap.Provenance(
                filePath: "Sources/MyModule/Foo+Hashable.swift",
                line: 3,
                kind: .extension
            )
        ]
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(
                entries: [entry("Foo", conformances: [.hashable], provenances: provenances)],
                parseFailures: []
            )
        )
        #expect(output.contains("Sources/MyModule/Foo.swift:1 (primary)"))
        #expect(output.contains("Sources/MyModule/Foo+Hashable.swift:3 (extension)"))
    }

    // MARK: - Idempotence

    @Test func emittingTwiceProducesByteIdenticalOutput() {
        let map = ConformanceMap(
            entries: [
                entry("Bar", conformances: [.hashable]),
                entry("Foo", conformances: [.equatable])
            ],
            parseFailures: []
        )
        let firstRun = GeneratedFileEmitter.emit(target: "X", map: map)
        let secondRun = GeneratedFileEmitter.emit(target: "X", map: map)
        #expect(firstRun == secondRun)
    }

    // MARK: - Suppression markers

    @Test func suppressedTestEmitsCommentStubAndPreservesMarker() {
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(
                entries: [entry("Foo", conformances: [.equatable, .codable])],
                parseFailures: []
            ),
            suppressions: ["codable_Foo"]
        )
        // Equatable test still emitted.
        #expect(output.contains("@Test func equatable_Foo() async throws {"))
        // Codable test replaced by suppression marker + comment stub.
        #expect(output.contains("// proto-law-suppress: codable_Foo"))
        #expect(output.contains("(checkCodableProtocolLaws for Foo suppressed"))
        #expect(!output.contains("@Test func codable_Foo"))
    }

    // MARK: - Edge cases

    @Test func emptyMapEmitsHeaderAndImportsOnly() {
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(entries: [], parseFailures: [])
        )
        #expect(output.contains("// Types detected: 0"))
        #expect(output.contains("import ProtocolLawKit"))
        #expect(!output.contains("@Suite"))
    }

    @Test func parseFailuresAreSurfacedInHeader() {
        let map = ConformanceMap(
            entries: [],
            parseFailures: [
                ConformanceMap.ParseFailure(
                    filePath: "/path/Bad.swift",
                    message: "unreadable"
                )
            ]
        )
        let output = GeneratedFileEmitter.emit(target: "X", map: map)
        #expect(output.contains("Parse failures (1):"))
        #expect(output.contains("/path/Bad.swift: unreadable"))
    }

    @Test func iteratorProtocolOnlyEmitsNoEmitComment() {
        let output = GeneratedFileEmitter.emit(
            target: "X",
            map: ConformanceMap(
                entries: [entry("Cursor", conformances: [.iteratorProtocol])],
                parseFailures: []
            )
        )
        #expect(output.contains("// No emit-able stdlib conformance"))
        #expect(!output.contains("@Suite struct CursorProtocolLawTests"))
    }

    // MARK: - M3 derivation strategies

    @Test func caseIterableEntryEmitsAllCasesGenerator() {
        let output = GeneratedFileEmitter.emit(
            target: "X",
            map: ConformanceMap(
                entries: [entry("Status", conformances: [.equatable], strategy: .caseIterable)],
                parseFailures: []
            )
        )
        #expect(output.contains("using: Gen<Status>.element(of: Status.allCases)"))
        #expect(!output.contains("Status.gen()"))
    }

    @Test func rawRepresentableEntryEmitsLiftedGenerator() {
        let output = GeneratedFileEmitter.emit(
            target: "X",
            map: ConformanceMap(
                entries: [entry("Direction", conformances: [.equatable], strategy: .rawRepresentable(.string))],
                parseFailures: []
            )
        )
        #expect(output.contains("Gen<Character>.letterOrNumber.string(of: 0...8)"))
        #expect(output.contains("compactMap { Direction(rawValue: $0) }"))
        #expect(!output.contains("Direction.gen()"))
    }

    @Test func intRawRepresentableEntryEmitsIntGenerator() {
        let output = GeneratedFileEmitter.emit(
            target: "X",
            map: ConformanceMap(
                entries: [entry("Code", conformances: [.equatable], strategy: .rawRepresentable(.int))],
                parseFailures: []
            )
        )
        #expect(output.contains("Gen<Int>.int()"))
        #expect(output.contains("compactMap { Code(rawValue: $0) }"))
    }

    @Test func todoEntryEmitsUserGenReference() {
        // .todo falls back to <TypeName>.gen() as the placeholder reference;
        // the user gets a compile error pointing at the missing symbol.
        let output = GeneratedFileEmitter.emit(
            target: "X",
            map: ConformanceMap(
                entries: [entry("Coordinate", conformances: [.equatable], strategy: .todo(reason: "test"))],
                parseFailures: []
            )
        )
        #expect(output.contains("using: Coordinate.gen()"))
    }
}
