import Foundation

/// Parses an existing `*.generated.swift` file for
/// `// proto-law-suppress: <protocol>_<TypeName>` markers and returns the
/// set of suppression keys (PRD §5.3 step 4 — "suppress noisy or wrong
/// suggestions inline ... the next regeneration honors").
///
/// M2 commit 5 stubs this to always return `[]` so the tool's write path
/// works end-to-end. Commit 6 fills in the actual parsing — the contract
/// here is stable so the emitter doesn't change.
enum SuppressionParser {

    static func parse(existingFileAt path: String) -> Set<String> {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }
        return parse(text: contents)
    }

    static func parse(text: String) -> Set<String> {
        // Match `// proto-law-suppress: <key>` lines. Keys are
        // `<protocol>_<TypeName>` matching `KnownProtocol.testNameFragment`
        // + `_` + Swift identifier. Tolerant of leading whitespace.
        var keys: Set<String> = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("// proto-law-suppress:") else { continue }
            let key = line
                .dropFirst("// proto-law-suppress:".count)
                .trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                keys.insert(key)
            }
        }
        return keys
    }
}
