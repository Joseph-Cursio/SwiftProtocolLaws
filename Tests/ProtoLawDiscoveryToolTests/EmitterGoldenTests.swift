import Testing
@testable import ProtoLawDiscoveryTool
@testable import ProtoLawCore

@Suite struct EmitterGoldenTests {

    // MARK: - Single-type happy paths

    @Test func emitsEquatableSuite() {
        let map = ConformanceMap(
            entries: [
                ConformanceMap.Entry(
                    typeName: "Foo",
                    conformances: [.equatable],
                    provenances: [
                        ConformanceMap.Provenance(
                            filePath: "Sources/MyModule/Foo.swift",
                            line: 1,
                            kind: .primary
                        )
                    ]
                )
            ],
            parseFailures: []
        )
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
        let entry = ConformanceMap.Entry(
            typeName: "Foo",
            conformances: [.hashable],  // post-dedupe (Hashable subsumes Equatable)
            provenances: [
                ConformanceMap.Provenance(
                    filePath: "Sources/MyModule/Foo.swift",
                    line: 5,
                    kind: .primary
                )
            ]
        )
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(entries: [entry], parseFailures: [])
        )
        #expect(output.contains("checkHashableProtocolLaws"))
        // Equatable check NOT emitted — subsumed.
        #expect(!output.contains("checkEquatableProtocolLaws"))
    }

    @Test func emitsCodableAndEquatable() {
        let entry = ConformanceMap.Entry(
            typeName: "Record",
            conformances: [.equatable, .codable],
            provenances: [
                ConformanceMap.Provenance(
                    filePath: "Sources/MyModule/Record.swift",
                    line: 10,
                    kind: .primary
                )
            ]
        )
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(entries: [entry], parseFailures: [])
        )
        #expect(output.contains("@Test func equatable_Record() async throws {"))
        #expect(output.contains("@Test func codable_Record() async throws {"))
        // Order — Equatable comes first per KnownProtocol.allCases.
        let equatableRange = output.range(of: "equatable_Record")!
        let codableRange = output.range(of: "codable_Record")!
        #expect(equatableRange.lowerBound < codableRange.lowerBound)
    }

    // MARK: - Provenance comments

    @Test func provenanceCommentListsAllSources() {
        let entry = ConformanceMap.Entry(
            typeName: "Foo",
            conformances: [.hashable],
            provenances: [
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
        )
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(entries: [entry], parseFailures: [])
        )
        #expect(output.contains("Sources/MyModule/Foo.swift:1 (primary)"))
        #expect(output.contains("Sources/MyModule/Foo+Hashable.swift:3 (extension)"))
    }

    // MARK: - Idempotence

    @Test func emittingTwiceProducesByteIdenticalOutput() {
        let map = ConformanceMap(
            entries: [
                ConformanceMap.Entry(
                    typeName: "Bar",
                    conformances: [.hashable],
                    provenances: [ConformanceMap.Provenance(
                        filePath: "/p/Bar.swift", line: 1, kind: .primary
                    )]
                ),
                ConformanceMap.Entry(
                    typeName: "Foo",
                    conformances: [.equatable],
                    provenances: [ConformanceMap.Provenance(
                        filePath: "/p/Foo.swift", line: 1, kind: .primary
                    )]
                )
            ],
            parseFailures: []
        )
        let firstRun = GeneratedFileEmitter.emit(target: "X", map: map)
        let secondRun = GeneratedFileEmitter.emit(target: "X", map: map)
        #expect(firstRun == secondRun)
    }

    // MARK: - Suppression markers

    @Test func suppressedTestEmitsCommentStubAndPreservesMarker() {
        let map = ConformanceMap(
            entries: [
                ConformanceMap.Entry(
                    typeName: "Foo",
                    conformances: [.equatable, .codable],
                    provenances: [ConformanceMap.Provenance(
                        filePath: "Sources/MyModule/Foo.swift",
                        line: 1,
                        kind: .primary
                    )]
                )
            ],
            parseFailures: []
        )
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: map,
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
        // Pure IteratorProtocol conformance has no usable emit (kit's
        // checkIteratorProtocolLaws needs a host Sequence).
        let entry = ConformanceMap.Entry(
            typeName: "Cursor",
            conformances: [.iteratorProtocol],
            provenances: [ConformanceMap.Provenance(
                filePath: "/p/Cursor.swift", line: 1, kind: .primary
            )]
        )
        let output = GeneratedFileEmitter.emit(
            target: "X",
            map: ConformanceMap(entries: [entry], parseFailures: [])
        )
        #expect(output.contains("// No emit-able stdlib conformance"))
        #expect(!output.contains("@Suite struct CursorProtocolLawTests"))
    }
}
