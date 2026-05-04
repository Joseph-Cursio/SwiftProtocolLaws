import Testing
@testable import PropertyLawDiscoveryTool

struct ToolInvocationTests {

    @Test func parsesMinimalInvocation() throws {
        let invocation = try ToolInvocation(arguments: [
            "--target", "MyModule",
            "--output", "/tmp/out.swift",
            "--source-files", "/a/b.swift", "/a/c.swift"
        ])
        #expect(invocation.target == "MyModule")
        #expect(invocation.outputPath == "/tmp/out.swift")
        #expect(invocation.sourceFiles == ["/a/b.swift", "/a/c.swift"])
    }

    @Test func parsesEmptySourceFilesList() throws {
        let invocation = try ToolInvocation(arguments: [
            "--target", "MyModule",
            "--output", "/tmp/out.swift",
            "--source-files"
        ])
        #expect(invocation.sourceFiles == [])
    }

    @Test func sourceFilesTerminatesAtNextFlag() throws {
        // --source-files greedily consumes positional args until the next
        // `--`-prefixed token. Order of flags shouldn't matter.
        let invocation = try ToolInvocation(arguments: [
            "--source-files", "/x.swift", "/y.swift",
            "--target", "MyModule",
            "--output", "/tmp/out.swift"
        ])
        #expect(invocation.sourceFiles == ["/x.swift", "/y.swift"])
        #expect(invocation.target == "MyModule")
    }

    @Test func missingTargetThrows() {
        #expect(throws: InvocationError.self) {
            _ = try ToolInvocation(arguments: ["--output", "/tmp/out.swift"])
        }
    }

    @Test func missingOutputThrows() {
        #expect(throws: InvocationError.self) {
            _ = try ToolInvocation(arguments: ["--target", "MyModule"])
        }
    }

    @Test func unknownArgumentThrows() {
        #expect(throws: InvocationError.self) {
            _ = try ToolInvocation(arguments: [
                "--target", "MyModule",
                "--output", "/tmp/out.swift",
                "--unknown-flag", "x"
            ])
        }
    }

    @Test func missingValueAfterFlagThrows() {
        #expect(throws: InvocationError.self) {
            _ = try ToolInvocation(arguments: ["--target"])
        }
    }

    // MARK: - PRD §5.4 advisory flags (M4)

    @Test func advisoryDefaultsToOff() throws {
        let invocation = try ToolInvocation(arguments: [
            "--target", "MyModule",
            "--output", "/tmp/out.swift",
            "--source-files", "/a.swift"
        ])
        #expect(invocation.advisory == false)
        #expect(invocation.advisoryMinConfidence == .high)
    }

    @Test func parsesAdvisoryFlag() throws {
        let invocation = try ToolInvocation(arguments: [
            "--target", "MyModule",
            "--output", "/tmp/out.swift",
            "--advisory",
            "--source-files", "/a.swift"
        ])
        #expect(invocation.advisory)
        #expect(invocation.advisoryMinConfidence == .high)
    }

    @Test func parsesAdvisoryMinConfidence() throws {
        let lowInvocation = try ToolInvocation(arguments: [
            "--target", "M", "--output", "/tmp/o.swift",
            "--advisory", "--advisory-min", "low",
            "--source-files"
        ])
        #expect(lowInvocation.advisoryMinConfidence == .low)

        let mediumInvocation = try ToolInvocation(arguments: [
            "--target", "M", "--output", "/tmp/o.swift",
            "--advisory", "--advisory-min", "medium",
            "--source-files"
        ])
        #expect(mediumInvocation.advisoryMinConfidence == .medium)
    }

    @Test func invalidAdvisoryMinThrows() {
        #expect(throws: InvocationError.self) {
            _ = try ToolInvocation(arguments: [
                "--target", "M", "--output", "/tmp/o.swift",
                "--advisory-min", "totally-invalid",
                "--source-files"
            ])
        }
    }

    @Test func missingValueAfterAdvisoryMinThrows() {
        #expect(throws: InvocationError.self) {
            _ = try ToolInvocation(arguments: [
                "--target", "M", "--output", "/tmp/o.swift",
                "--advisory-min"
            ])
        }
    }
}
