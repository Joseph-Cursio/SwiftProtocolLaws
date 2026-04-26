import Testing
@testable import ProtoLawDiscoveryTool

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
}
