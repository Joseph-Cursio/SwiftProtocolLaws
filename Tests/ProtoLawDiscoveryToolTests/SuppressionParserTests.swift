import Testing
@testable import ProtoLawDiscoveryTool

@Suite struct SuppressionParserTests {

    @Test func extractsSingleMarker() {
        let text = """
            @Suite struct FooProtocolLawTests {
                // proto-law-suppress: hashable_Foo
                @Test func equatable_Foo() async throws { /* ... */ }
            }
            """
        let keys = SuppressionParser.parse(text: text)
        #expect(keys == ["hashable_Foo"])
    }

    @Test func extractsMultipleMarkers() {
        let text = """
            @Suite struct FooProtocolLawTests {
                // proto-law-suppress: hashable_Foo
                // proto-law-suppress: codable_Foo
            }
            """
        let keys = SuppressionParser.parse(text: text)
        #expect(keys == ["hashable_Foo", "codable_Foo"])
    }

    @Test func ignoresUnrelatedComments() {
        let text = """
            // some unrelated comment
            // proto-law-suppress: equatable_Foo
            // FIXME: nothing
            """
        let keys = SuppressionParser.parse(text: text)
        #expect(keys == ["equatable_Foo"])
    }

    @Test func toleratesLeadingWhitespace() {
        let text = "    // proto-law-suppress: equatable_Foo"
        let keys = SuppressionParser.parse(text: text)
        #expect(keys == ["equatable_Foo"])
    }

    @Test func emptyMarkerKeyIsIgnored() {
        let text = "// proto-law-suppress: "
        let keys = SuppressionParser.parse(text: text)
        #expect(keys == [])
    }

    @Test func nonExistentFileReturnsEmptySet() {
        let keys = SuppressionParser.parse(existingFileAt: "/nonexistent/path.swift")
        #expect(keys == [])
    }
}
