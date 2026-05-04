import Testing
@testable import PropertyLawDiscoveryTool
@testable import PropertyLawCore

/// Unit tests for `RoundTripSuggester` (PRD §5.5 cross-function round-
/// trip discovery, M5). Operates on synthetic `ConformanceMap`s — the
/// integration with `ModuleScanner` lives in `ModuleScannerRoundTripTests`.
struct RoundTripSuggesterTests {

    // MARK: - HIGH confidence (signature inverse + naming pair)

    @Test func suggestsRoundTripForEncodeDecodePair() throws {
        let map = makeMap(memberFunctions: [
            "Codec": [
                signature(name: "encode", params: ["Foo"], ret: "Data", isStatic: true),
                signature(name: "decode", params: ["Data"], ret: "Foo", isStatic: true)
            ]
        ])
        let suggestions = RoundTripSuggester.suggest(from: map)
        try #require(suggestions.count == 1)
        let suggestion = suggestions[0]
        #expect(suggestion.scope == .type("Codec"))
        #expect(suggestion.confidence == .high)
        #expect(suggestion.forward.name == "encode")
        #expect(suggestion.backward.name == "decode")
    }

    @Test func suggestsRoundTripForSerializeDeserializePair() throws {
        let map = makeMap(topLevelFunctions: [
            signature(name: "serialize", params: ["Foo"], ret: "Data"),
            signature(name: "deserialize", params: ["Data"], ret: "Foo")
        ])
        let suggestions = RoundTripSuggester.suggest(from: map)
        try #require(suggestions.count == 1)
        #expect(suggestions[0].scope == .module)
        #expect(suggestions[0].confidence == .high)
    }

    // MARK: - HIGH via @Discoverable group

    @Test func discoverableGroupTriggersHighWithoutNamePair() throws {
        // Names not in the curated table; group attribute supplies the
        // explicit confirmation that the inverse signature is intentional.
        let map = makeMap(memberFunctions: [
            "Foo": [
                signature(name: "toBytes", params: ["Foo"], ret: "Data",
                          isStatic: true, group: "ser"),
                signature(name: "fromBytes", params: ["Data"], ret: "Foo",
                          isStatic: true, group: "ser")
            ]
        ])
        let suggestions = RoundTripSuggester.suggest(from: map)
        try #require(suggestions.count == 1)
        #expect(suggestions[0].confidence == .high)
    }

    @Test func mismatchedGroupValuesDoNotPromote() throws {
        let map = makeMap(memberFunctions: [
            "Foo": [
                signature(name: "toBytes", params: ["Foo"], ret: "Data",
                          isStatic: true, group: "groupA"),
                signature(name: "fromBytes", params: ["Data"], ret: "Foo",
                          isStatic: true, group: "groupB")
            ]
        ])
        // Signatures invert → MEDIUM. No naming pair, no group match.
        // Default floor (HIGH) filters this out.
        #expect(RoundTripSuggester.suggest(from: map).isEmpty)
        let lowered = RoundTripSuggester.suggest(from: map, minConfidence: .medium)
        try #require(lowered.count == 1)
        #expect(lowered[0].confidence == .medium)
    }

    // MARK: - MEDIUM confidence (signature only)

    /// Signatures invert; names aren't in the curated table; no group.
    /// HIGH floor filters → 0; MEDIUM and LOW floors emit a single
    /// MEDIUM-confidence pair.
    @Test(arguments: [
        (SuggestionConfidence.high, 0),
        (.medium, 1),
        (.low, 1)
    ])
    func signatureOnlyPairFiltersByFloor(
        floor: SuggestionConfidence,
        expectedCount: Int
    ) throws {
        let map = makeMap(memberFunctions: [
            "Box": [
                signature(name: "wrap", params: ["Foo"], ret: "Data", isStatic: true),
                signature(name: "unwrap", params: ["Data"], ret: "Foo", isStatic: true)
            ]
        ])
        let suggestions = RoundTripSuggester.suggest(from: map, minConfidence: floor)
        try #require(suggestions.count == expectedCount)
        if expectedCount > 0 {
            #expect(suggestions[0].confidence == .medium)
        }
    }

    // MARK: - LOW confidence (name pair only)

    /// push/pop is a curated pair, but the typical Stack shape is
    /// `push(Element)` (Void return) and `pop()` (zero params); no
    /// signature inverse → LOW. HIGH and MEDIUM floors filter the
    /// suggestion; LOW floor emits it with forward = push, backward = pop.
    @Test(arguments: [
        (SuggestionConfidence.high, 0),
        (.medium, 0),
        (.low, 1)
    ])
    func nameOnlyPairFiltersByFloor(
        floor: SuggestionConfidence,
        expectedCount: Int
    ) throws {
        let map = makeMap(memberFunctions: [
            "Stack": [
                signature(name: "push", params: ["Element"], ret: "Void"),
                signature(name: "pop", params: [], ret: "Element?")
            ]
        ])
        let suggestions = RoundTripSuggester.suggest(from: map, minConfidence: floor)
        try #require(suggestions.count == expectedCount)
        if expectedCount > 0 {
            #expect(suggestions[0].confidence == .low)
            #expect(suggestions[0].forward.name == "push")
            #expect(suggestions[0].backward.name == "pop")
        }
    }

    // MARK: - Symmetric dedupe

    @Test func emitsOneSuggestionPerUnorderedPair() throws {
        // The same encode/decode pair appears once regardless of
        // declaration order in the input list.
        let map = makeMap(memberFunctions: [
            "Codec": [
                signature(name: "decode", params: ["Data"], ret: "Foo", isStatic: true),
                signature(name: "encode", params: ["Foo"], ret: "Data", isStatic: true)
            ]
        ])
        let suggestions = RoundTripSuggester.suggest(from: map)
        try #require(suggestions.count == 1)
        // Naming-pair table dictates encode = forward regardless of input order.
        #expect(suggestions[0].forward.name == "encode")
        #expect(suggestions[0].backward.name == "decode")
    }

    // MARK: - Scope separation

    @Test func typeAndModuleScopesArePairedSeparately() throws {
        // A `Codec.encode` member must NOT pair with a top-level `decode`
        // free function. Same-scope pairing only.
        let map = makeMap(
            memberFunctions: [
                "Codec": [
                    signature(name: "encode", params: ["Foo"], ret: "Data", isStatic: true)
                ]
            ],
            topLevelFunctions: [
                signature(name: "decode", params: ["Data"], ret: "Foo")
            ]
        )
        #expect(RoundTripSuggester.suggest(from: map).isEmpty)
    }

    @Test func emitsSuggestionsFromBothScopesInOnePass() throws {
        let map = makeMap(
            memberFunctions: [
                "Codec": [
                    signature(name: "encode", params: ["Foo"], ret: "Data", isStatic: true),
                    signature(name: "decode", params: ["Data"], ret: "Foo", isStatic: true)
                ]
            ],
            topLevelFunctions: [
                signature(name: "serialize", params: ["Bar"], ret: "Data"),
                signature(name: "deserialize", params: ["Data"], ret: "Bar")
            ]
        )
        let suggestions = RoundTripSuggester.suggest(from: map)
        try #require(suggestions.count == 2)
        #expect(suggestions[0].scope == .type("Codec"))
        #expect(suggestions[1].scope == .module)
    }

    // MARK: - Determinism

    @Test func suggestionsAreSortedByScopeThenForwardName() throws {
        // Scope sort: per-type before module. Within per-type: type name
        // ASC. Within type: forward name ASC.
        let map = makeMap(
            memberFunctions: [
                "Banana": [
                    signature(name: "encode", params: ["Foo"], ret: "Data", isStatic: true),
                    signature(name: "decode", params: ["Data"], ret: "Foo", isStatic: true)
                ],
                "Apple": [
                    signature(name: "encode", params: ["Foo"], ret: "Data", isStatic: true),
                    signature(name: "decode", params: ["Data"], ret: "Foo", isStatic: true)
                ]
            ],
            topLevelFunctions: [
                signature(name: "serialize", params: ["Bar"], ret: "Data"),
                signature(name: "deserialize", params: ["Data"], ret: "Bar")
            ]
        )
        let suggestions = RoundTripSuggester.suggest(from: map)
        // Apple → Banana → module. Single whole-list assertion makes
        // the expected sort order explicit on regression instead of
        // pinning each index separately.
        #expect(
            suggestions.map(\.scope) == [.type("Apple"), .type("Banana"), .module]
        )
    }

    // MARK: - Empty / no-pair inputs

    @Test func emptyMapProducesNoSuggestions() {
        #expect(RoundTripSuggester.suggest(from: makeMap()).isEmpty)
    }

    @Test func unrelatedFunctionsProduceNoSuggestions() {
        let map = makeMap(memberFunctions: [
            "Foo": [
                signature(name: "describe", params: [], ret: "String"),
                signature(name: "render", params: ["Style"], ret: "View")
            ]
        ])
        #expect(RoundTripSuggester.suggest(from: map).isEmpty)
    }

    // MARK: - Helpers

    private func signature(
        name: String,
        params: [String],
        ret: String,
        isStatic: Bool = false,
        group: String? = nil
    ) -> FunctionSignature {
        FunctionSignature(
            name: name,
            parameterTypes: params,
            returnType: ret,
            isStatic: isStatic,
            group: group
        )
    }

    private func makeMap(
        memberFunctions: [String: [FunctionSignature]] = [:],
        topLevelFunctions: [FunctionSignature] = []
    ) -> ConformanceMap {
        ConformanceMap(
            entries: [],
            parseFailures: [],
            witnesses: [:],
            memberFunctions: memberFunctions,
            topLevelFunctions: topLevelFunctions
        )
    }
}
