import Foundation
import Testing
@testable import ProtoLawDiscoveryTool
@testable import ProtoLawCore

struct ModuleScannerTests {

    // MARK: - Single-file conformances

    @Test func detectsStructConformances() throws {
        let dir = try makeFixtureDir([
            "Foo.swift": """
                struct Foo: Equatable, Hashable {
                    let value: Int
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        let entry = map.entries[0]
        #expect(entry.typeName == "Foo")
        #expect(entry.conformances == [.hashable])  // most-specific dedupe
        #expect(entry.provenances.count == 1)
        #expect(entry.provenances[0].kind == .primary)
        #expect(entry.provenances[0].line == 1)
    }

    @Test func detectsEnumConformances() throws {
        let dir = try makeFixtureDir([
            "Direction.swift": """
                enum Direction: String, Codable, CaseIterable {
                    case north, south
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        #expect(map.entries[0].conformances == [.codable])
    }

    // MARK: - Cross-file extension aggregation (the M2 unlock)

    @Test func aggregatesExtensionsAcrossFiles() throws {
        let dir = try makeFixtureDir([
            "Foo.swift": """
                struct Foo {
                    let value: Int
                }
                """,
            "Foo+Equatable.swift": """
                extension Foo: Equatable {
                    static func == (lhs: Foo, rhs: Foo) -> Bool { lhs.value == rhs.value }
                }
                """,
            "Foo+Hashable.swift": """
                extension Foo: Hashable {
                    func hash(into hasher: inout Hasher) { hasher.combine(value) }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        let entry = map.entries[0]
        #expect(entry.typeName == "Foo")
        #expect(entry.conformances == [.hashable])
        #expect(entry.provenances.count == 3)  // primary + two extensions
        // Sorted: file paths first, then line.
        #expect(entry.provenances.contains { $0.kind == .primary })
        let extensionCount = entry.provenances.filter { $0.kind == .extension }.count
        #expect(extensionCount == 2)
    }

    @Test func conditionalConformanceExtensionsAreSkipped() throws {
        // PRD §4.4: conditional conformances (`extension Foo: Equatable
        // where T: Equatable`) aren't unconditional — emitting an
        // unconditional check would be wrong. M3 handles via
        // @LawGenerator(bindings:).
        let dir = try makeFixtureDir([
            "Container.swift": """
                struct Container<T> {
                    let item: T
                }
                """,
            "Container+Conditional.swift": """
                extension Container: Equatable where T: Equatable {
                    static func == (lhs: Container, rhs: Container) -> Bool { false }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        // Primary decl recorded (no inheritance), conditional extension
        // skipped → no recognized conformances.
        #expect(map.entries[0].conformances == [])
    }

    // MARK: - Multiple types

    @Test func multipleTypesYieldMultipleEntries() throws {
        let dir = try makeFixtureDir([
            "Types.swift": """
                struct Foo: Equatable {
                    let value: Int
                }
                struct Bar: Hashable {
                    let other: Int
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 2)
        // Sorted alphabetically.
        #expect(map.entries[0].typeName == "Bar")
        #expect(map.entries[0].conformances == [.hashable])
        #expect(map.entries[1].typeName == "Foo")
        #expect(map.entries[1].conformances == [.equatable])
    }

    // MARK: - Encodable + Decodable pairing

    @Test func encodableDecodablePairResolvesToCodable() throws {
        let dir = try makeFixtureDir([
            "Record.swift": """
                struct Record: Encodable, Decodable {
                    let id: Int
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        #expect(map.entries[0].conformances == [.codable])
    }

    // MARK: - Idempotence

    @Test func sortedFileOrderProducesDeterministicOutput() throws {
        let dir = try makeFixtureDir([
            "z.swift": "struct Last: Equatable { let v: Int }",
            "a.swift": "struct First: Equatable { let v: Int }"
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let paths = filePaths(in: dir)
        // Scan twice with shuffled and sorted inputs — output should match.
        let sortedScan = ModuleScanner.scan(sourceFiles: paths.sorted())
        let reversedScan = ModuleScanner.scan(sourceFiles: paths.sorted().reversed())
        #expect(sortedScan == reversedScan)
    }

    // MARK: - Error tolerance

    @Test func unreadableFileSurfacesAsParseFailureNotFatal() throws {
        let map = ModuleScanner.scan(sourceFiles: ["/nonexistent/path/Foo.swift"])
        #expect(map.entries.isEmpty)
        try #require(map.parseFailures.count == 1)
        #expect(map.parseFailures.first?.filePath == "/nonexistent/path/Foo.swift")
    }

    // MARK: - Helpers

    private func makeFixtureDir(_ files: [String: String]) throws -> String {
        let dir = NSTemporaryDirectory().appending("ProtoLawScan-\(UUID().uuidString)/")
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
        for (name, contents) in files {
            try contents.write(
                toFile: dir + name,
                atomically: true,
                encoding: .utf8
            )
        }
        return dir
    }

    private func filePaths(in dir: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir).map { dir + $0 }) ?? []
    }
}
