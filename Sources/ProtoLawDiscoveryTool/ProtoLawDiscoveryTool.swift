import Foundation

/// Whole-module conformance-discovery tool (PRD §5.3 Discovery Mode).
///
/// Invoked by `ProtoLawDiscoveryPlugin` via `swift package protolawcheck
/// discover --target <name>`. The plugin gathers source-file paths from
/// the PluginContext and forwards them as positional arguments after the
/// `--source-files` separator. This tool walks them, builds a
/// `ConformanceMap`, applies any suppression markers found in an existing
/// output file, and writes the rendered output.
@main
struct ProtoLawDiscoveryTool {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty || args.first == "--help" || args.first == "-h" {
            printUsage()
            return
        }

        let invocation = try ToolInvocation(arguments: args)
        let map = ModuleScanner.scan(sourceFiles: invocation.sourceFiles)
        let suppressions = SuppressionParser.parse(existingFileAt: invocation.outputPath)
        let output = GeneratedFileEmitter.emit(
            target: invocation.target,
            map: map,
            suppressions: suppressions
        )
        try writeOutput(output, to: invocation.outputPath)
        printSummary(invocation: invocation, map: map, suppressions: suppressions)

        // PRD §5.4 advisory pass — opt-in, writes to stderr only so the
        // generated file stays byte-identical regardless of `--advisory`.
        if invocation.advisory {
            let suggestions = AdvisorySuggester.suggest(
                from: map,
                minConfidence: invocation.advisoryMinConfidence
            )
            printAdvisory(suggestions)
        }
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
                --advisory                Optional. Emit missing-conformance suggestions
                                          to stderr (PRD §5.4). Off by default. Output
                                          is informational only and does not change the
                                          generated file.
                --advisory-min <level>    Optional. Minimum confidence floor: low, medium,
                                          or high. Defaults to high. Lowers the bar for
                                          which advisory suggestions are emitted.
            """
        FileHandle.standardOutput.write(Data((usage + "\n").utf8))
    }

    /// Writes `contents` to `path`, creating parent directories as needed.
    private static func writeOutput(_ contents: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func printSummary(
        invocation: ToolInvocation,
        map: ConformanceMap,
        suppressions: Set<String>
    ) {
        var lines: [String] = []
        lines.append("ProtoLawDiscoveryTool: wrote \(invocation.outputPath)")
        lines.append("  target: \(invocation.target)")
        lines.append("  source files scanned: \(invocation.sourceFiles.count)")
        lines.append("  types detected: \(map.entries.count)")
        if !map.parseFailures.isEmpty {
            lines.append("  parse failures: \(map.parseFailures.count)")
        }
        if !suppressions.isEmpty {
            lines.append("  suppressions preserved: \(suppressions.count)")
        }
        // PRD §5.7 weak-generator telemetry — list types that need a
        // user-supplied gen() because no derivation strategy applied.
        let todoEntries = map.entries.filter { entry in
            if case .todo = entry.derivationStrategy { return true }
            return false
        }
        if !todoEntries.isEmpty {
            lines.append("  types needing manual gen() (\(todoEntries.count)):")
            for entry in todoEntries {
                lines.append("    - \(entry.typeName)")
            }
        }
        FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    /// Render advisory suggestions as Swift-compiler-style `note:` lines
    /// on stderr. One block per suggestion with two indented detail
    /// lines — matches PRD §5.4's "informational, never a test failure"
    /// framing without ever touching the generated file.
    private static func printAdvisory(_ suggestions: [Suggestion]) {
        guard !suggestions.isEmpty else { return }
        var lines: [String] = []
        lines.append("ProtoLawDiscoveryTool: \(suggestions.count) advisory suggestion(s):")
        for suggestion in suggestions {
            let proto = suggestion.suggestedProtocol
            lines.append(
                "  note: \(suggestion.typeName) \(suggestion.evidence) "
                + "but does not declare \(proto.declarationName)."
            )
            lines.append(
                "        Consider conforming and running \(proto.checkFunctionName) "
                + "to verify the laws hold."
            )
            lines.append(
                "        confidence: \(suggestion.confidence.rawValue)"
            )
        }
        FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    }
}

/// Argv-parsed invocation. Plugin → tool argv shape:
/// `--target <name> --output <path> [--advisory] [--advisory-min <level>]
///  --source-files <p1> <p2> ...`
struct ToolInvocation: Sendable {
    let target: String
    let outputPath: String
    let sourceFiles: [String]
    let advisory: Bool
    let advisoryMinConfidence: SuggestionConfidence

    init(arguments: [String]) throws {
        var target: String?
        var outputPath: String?
        var sourceFiles: [String] = []
        var advisory = false
        var advisoryMin: SuggestionConfidence = .high

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
            case "--advisory":
                advisory = true
            case "--advisory-min":
                index += 1
                guard index < arguments.count else {
                    throw InvocationError.missingValue("--advisory-min")
                }
                guard let level = SuggestionConfidence(rawValue: arguments[index]) else {
                    throw InvocationError.invalidValue(
                        flag: "--advisory-min",
                        value: arguments[index],
                        allowed: "low | medium | high"
                    )
                }
                advisoryMin = level
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
        self.advisory = advisory
        self.advisoryMinConfidence = advisoryMin
    }
}

enum InvocationError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknownArgument(String)
    case invalidValue(flag: String, value: String, allowed: String)

    var description: String {
        switch self {
        case .missingValue(let flag): return "missing value for \(flag)"
        case .unknownArgument(let arg): return "unknown argument: \(arg)"
        case .invalidValue(let flag, let value, let allowed):
            return "invalid value '\(value)' for \(flag); allowed: \(allowed)"
        }
    }
}
