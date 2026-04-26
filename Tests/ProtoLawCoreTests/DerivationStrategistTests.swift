import Testing
@testable import ProtoLawCore

struct DerivationStrategistTests {

    // MARK: - Strategy A: user-provided gen() wins unconditionally

    @Test func userGenWinsEvenForCaseIterableEnum() {
        // Even a CaseIterable enum yields .userGen when the user supplies
        // gen() — the user's intent always wins.
        let shape = TypeShape(
            name: "Status",
            kind: .enum,
            inheritedTypes: ["CaseIterable"],
            hasUserGen: true
        )
        #expect(DerivationStrategist.strategy(for: shape) == .userGen)
    }

    @Test func userGenWinsForStruct() {
        let shape = TypeShape(
            name: "Foo",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: true
        )
        #expect(DerivationStrategist.strategy(for: shape) == .userGen)
    }

    // MARK: - Strategy B: CaseIterable enums

    @Test func caseIterableEnumDerives() {
        let shape = TypeShape(
            name: "Direction",
            kind: .enum,
            inheritedTypes: ["CaseIterable", "Equatable"],
            hasUserGen: false
        )
        #expect(DerivationStrategist.strategy(for: shape) == .caseIterable)
    }

    @Test func caseIterableStructDoesNotDeriveAsCaseIterable() {
        // CaseIterable is meaningless on a struct; falls through to .todo.
        let shape = TypeShape(
            name: "Foo",
            kind: .struct,
            inheritedTypes: ["CaseIterable"],
            hasUserGen: false
        )
        guard case .todo = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo for CaseIterable struct")
            return
        }
    }

    // MARK: - Strategy C: RawRepresentable enums

    @Test func intRawEnumDerives() {
        let shape = TypeShape(
            name: "Code",
            kind: .enum,
            inheritedTypes: ["Int", "Equatable"],
            hasUserGen: false
        )
        #expect(DerivationStrategist.strategy(for: shape) == .rawRepresentable(.int))
    }

    @Test func stringRawEnumDerives() {
        let shape = TypeShape(
            name: "Status",
            kind: .enum,
            inheritedTypes: ["String", "Codable"],
            hasUserGen: false
        )
        #expect(DerivationStrategist.strategy(for: shape) == .rawRepresentable(.string))
    }

    @Test func allRawTypesAreRecognized() {
        for rawType in RawType.allCases {
            let shape = TypeShape(
                name: "Test",
                kind: .enum,
                inheritedTypes: [rawType.rawValue],
                hasUserGen: false
            )
            #expect(DerivationStrategist.strategy(for: shape) == .rawRepresentable(rawType))
        }
    }

    @Test func caseIterableSubsumesRawRepresentable() {
        // When both CaseIterable and a known raw type appear, CaseIterable
        // wins (Strategy B before Strategy C in the priority order — and
        // CaseIterable produces a stronger distribution per PRD §5.7).
        let shape = TypeShape(
            name: "Bits",
            kind: .enum,
            inheritedTypes: ["CaseIterable", "Int"],
            hasUserGen: false
        )
        #expect(DerivationStrategist.strategy(for: shape) == .caseIterable)
    }

    // MARK: - Strategy D: .todo fallback

    @Test func plainStructFallsThroughToTodo() {
        let shape = TypeShape(
            name: "Coordinate",
            kind: .struct,
            inheritedTypes: ["Equatable", "Hashable"],
            hasUserGen: false
        )
        guard case .todo(let reason) = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo")
            return
        }
        #expect(reason.contains("Coordinate"))
        #expect(reason.contains("memberwise"))
    }

    @Test func plainEnumWithoutCaseIterableOrRawFallsThroughToTodo() {
        // Associated-value enum without CaseIterable + without recognized
        // raw type → .todo.
        let shape = TypeShape(
            name: "Either",
            kind: .enum,
            inheritedTypes: ["Equatable"],
            hasUserGen: false
        )
        guard case .todo(let reason) = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo")
            return
        }
        #expect(reason.contains("Either"))
        #expect(reason.contains("CaseIterable"))
    }

    @Test func unknownRawTypeFallsThroughToTodo() {
        // CustomRawType isn't in our RawType allCases — strategist
        // doesn't try to derive against arbitrary user types.
        let shape = TypeShape(
            name: "Foo",
            kind: .enum,
            inheritedTypes: ["CustomRawType", "Equatable"],
            hasUserGen: false
        )
        guard case .todo = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo")
            return
        }
    }

    // MARK: - RawType generator expressions

    @Test func intGeneratorExpressionMatchesUpstream() {
        #expect(RawType.int.generatorExpression == "Gen<Int>.int()")
    }

    @Test func boolGeneratorExpressionMatchesUpstream() {
        #expect(RawType.bool.generatorExpression == "Gen<Bool>.bool()")
    }

    @Test func stringGeneratorExpressionMatchesUpstream() {
        #expect(RawType.string.generatorExpression == "Gen<Character>.letterOrNumber.string(of: 0...8)")
    }

    @Test func fixedWidthIntGeneratorsUseTypedFactoryName() {
        // swift-property-based names them int8/int16/... not int(in:) on
        // the typed extensions.
        #expect(RawType.int8.generatorExpression == "Gen<Int8>.int8()")
        #expect(RawType.uint64.generatorExpression == "Gen<UInt64>.uint64()")
    }
}
