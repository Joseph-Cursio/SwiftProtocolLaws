import Foundation

/// Whole-module conformance-discovery tool (PRD §5.3 Discovery Mode).
///
/// Invoked by `ProtoLawDiscoveryPlugin` via `swift package protolawcheck
/// discover --target <name>`. The plugin gathers source-file paths from the
/// PluginContext and forwards them as positional arguments after a
/// `--source-files` separator; this tool walks them, builds a
/// `ConformanceMap`, and emits the generated test file.
///
/// Commit 1 ships the executable scaffold + argparse skeleton. Commits 3–5
/// fill in the SwiftSyntax scanner, the emitter, and the suppression
/// round-trip respectively.
@main
struct ProtoLawDiscoveryTool {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty || args.first == "--help" || args.first == "-h" {
            printUsage()
            return
        }

        let invocation = try ToolInvocation(arguments: args)
        let header = """
            // ProtoLawDiscoveryTool scaffold (commit 1/6).
            // target: \(invocation.target)
            // output: \(invocation.outputPath)
            // sourceFiles.count: \(invocation.sourceFiles.count)
            // — module scanner, emitter, plugin wiring land in commits 3–5.
            """
        FileHandle.standardOutput.write(Data((header + "\n").utf8))
    }

    static func printUsage() {
        let usage = """
            ProtoLawDiscoveryTool — walks a target's source files and emits
            ProtocolLawKit test calls for each detected conformance.

            Usage (typical, via plugin):
                swift package protolawcheck discover --target <Target>

            Direct invocation:
                ProtoLawDiscoveryTool \\
                    --target <Target> \\
                    --output <path/to/ProtocolLawTests.generated.swift> \\
                    --source-files <file1.swift> <file2.swift> ...

            Options:
                --target <name>           Required. The target whose conformances to scan.
                --output <path>           Required. Path to the generated file.
                --source-files <paths>... Required. Source paths the plugin discovers.
            """
        FileHandle.standardOutput.write(Data((usage + "\n").utf8))
    }
}

/// Argv-parsed invocation. Plugin → tool argv shape:
/// `--target <name> --output <path> --source-files <p1> <p2> ...`
struct ToolInvocation: Sendable {
    let target: String
    let outputPath: String
    let sourceFiles: [String]

    init(arguments: [String]) throws {
        var target: String?
        var outputPath: String?
        var sourceFiles: [String] = []

        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--target":
                index += 1
                guard index < arguments.count else {
                    throw InvocationError.missingValue("--target")
                }
                target = arguments[index]
            case "--output":
                index += 1
                guard index < arguments.count else {
                    throw InvocationError.missingValue("--output")
                }
                outputPath = arguments[index]
            case "--source-files":
                index += 1
                while index < arguments.count, !arguments[index].hasPrefix("--") {
                    sourceFiles.append(arguments[index])
                    index += 1
                }
                continue
            default:
                throw InvocationError.unknownArgument(arg)
            }
            index += 1
        }

        guard let target else { throw InvocationError.missingValue("--target") }
        guard let outputPath else { throw InvocationError.missingValue("--output") }
        self.target = target
        self.outputPath = outputPath
        self.sourceFiles = sourceFiles
    }
}

enum InvocationError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknownArgument(String)

    var description: String {
        switch self {
        case .missingValue(let flag): return "missing value for \(flag)"
        case .unknownArgument(let arg): return "unknown argument: \(arg)"
        }
    }
}
