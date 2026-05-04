import Testing
@testable import PropertyLawCore

/// Direct `#expect` pins on the rendered text. These guard against drift
/// in either the macro impl's `generatorExpression` or the discovery
/// plugin's `GeneratedFileEmitter.generatorExpression` — both delegate to
/// `MemberwiseEmitter.expression` so a single source of truth is fixed
/// here. (The `assertMacroExpansion`-based tests in
/// `MacroExpansionTests` and `EmitterGoldenTests` rely on
/// `XCTFail`-based string equality which Swift Testing's `@Test` doesn't
/// always pick up — this file is the actual drift guard.)
struct MemberwiseEmitterTests {

    @Test func singleMemberEmitsPlainMap() {
        let expr = MemberwiseEmitter.expression(
            typeName: "ID",
            members: [MemberSpec(name: "value", rawType: .int)]
        )
        #expect(expr == "Gen<Int>.int().map { ID(value: $0) }")
    }

    @Test func singleStringMemberLiftsThroughLetterOrNumberStringGenerator() {
        let expr = MemberwiseEmitter.expression(
            typeName: "Tag",
            members: [MemberSpec(name: "name", rawType: .string)]
        )
        #expect(expr == "Gen<Character>.letterOrNumber.string(of: 0...8).map { Tag(name: $0) }")
    }

    @Test func twoMembersUseZipWithPositionalArguments() {
        let expr = MemberwiseEmitter.expression(
            typeName: "Coordinate",
            members: [
                MemberSpec(name: "easting", rawType: .int),
                MemberSpec(name: "northing", rawType: .int)
            ]
        )
        let expected = """
            zip(Gen<Int>.int(), Gen<Int>.int())
                        .map { Coordinate(easting: $0.0, northing: $0.1) }
            """
        #expect(expr == expected)
    }

    @Test func threeMembersWithMixedRawTypes() {
        let expr = MemberwiseEmitter.expression(
            typeName: "Record",
            members: [
                MemberSpec(name: "id", rawType: .int),
                MemberSpec(name: "label", rawType: .string),
                MemberSpec(name: "active", rawType: .bool)
            ]
        )
        let expected = """
            zip(Gen<Int>.int(), Gen<Character>.letterOrNumber.string(of: 0...8), Gen<Bool>.bool())
                        .map { Record(id: $0.0, label: $0.1, active: $0.2) }
            """
        #expect(expr == expected)
    }

    @Test func tenMembersAtArityLimitStillEmits() {
        let members = (0..<10).map { idx in
            MemberSpec(name: "m\(idx)", rawType: .int)
        }
        let expr = MemberwiseEmitter.expression(typeName: "Wide", members: members)
        // The structure of the emit at arity 10: every positional `$0.N`
        // for N ∈ 0…9 appears, and the prefix is a 10-arg `zip(...)`.
        for index in 0...9 {
            #expect(expr.contains("$0.\(index)"))
            #expect(expr.contains("m\(index): $0.\(index)"))
        }
        #expect(expr.hasPrefix("zip("))
    }

    @Test func arityLimitMatchesUpstreamZipOverloadCount() {
        // The strategist enforces this; locking it in a test catches any
        // future drift if upstream `swift-property-based` adds an
        // 11-arity zip overload (or removes one) without us updating.
        #expect(DerivationStrategist.memberwiseArityLimit == 10)
    }
}
