# RegexTool

**Category:** Developer Productivity
**Risk Level:** low
**Requires Approval:** No
**Tool Identifier:** `regex`

## Overview

`RegexTool` applies regular expressions to text strings and file contents. It supports matching with capture groups, multi-line file search, and in-memory replacement (it never writes to disk). This is a purely read-only, computation-only tool suitable for automatic execution without user approval.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `match`, `search_file`, `replace`, `validate` |
| `pattern` | string | Yes | — | Regular expression pattern |
| `input` | string | No | — | Input string to match against (for `match`, `replace`, `validate`) |
| `file_path` | string | No | — | File path to search (for `search_file`) |
| `replacement` | string | No | — | Replacement string (for `replace`; use `$1`, `$2` for groups) |
| `flags` | string | No | `"i"` | Regex flags: `i` (case insensitive), `m` (multiline), `s` (dotAll) |

---

## Swift Implementation

```swift
import Foundation

struct RegexTool: AgentTool {

    let name = "regex"
    let toolDescription = "Apply regular expressions: match with capture groups, search files, replace in-memory, and validate patterns."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",      type: .string, description: "match | search_file | replace | validate",
                      required: true, enumValues: ["match", "search_file", "replace", "validate"]),
        ToolParameter(name: "pattern",     type: .string, description: "Regex pattern",                   required: true),
        ToolParameter(name: "input",       type: .string, description: "Input string",                    required: false),
        ToolParameter(name: "file_path",   type: .string, description: "File path to search",             required: false),
        ToolParameter(name: "replacement", type: .string, description: "Replacement template ($1, $2...)", required: false),
        ToolParameter(name: "flags",       type: .string, description: "Flags: i (case), m (multiline), s (dotAll)", required: false, defaultValue: ""),
    ]
    let requiresApproval = false
    let riskLevel: ToolRiskLevel = .low

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action  = arguments["action"]?.stringValue  else { throw ToolError.missingRequiredParameter("action") }
        guard let pattern = arguments["pattern"]?.stringValue else { throw ToolError.missingRequiredParameter("pattern") }

        let flagsStr = arguments["flags"]?.stringValue ?? ""
        var options: NSRegularExpression.Options = []
        if flagsStr.contains("i") { options.insert(.caseInsensitive) }
        if flagsStr.contains("m") { options.insert(.anchorsMatchLines) }
        if flagsStr.contains("s") { options.insert(.dotMatchesLineSeparators) }

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            return ToolResult(toolName: name, success: false, output: "Invalid regex pattern: \(error.localizedDescription)")
        }

        switch action {
        case "match":
            guard let input = arguments["input"]?.stringValue else { throw ToolError.missingRequiredParameter("input") }
            return matchString(regex: regex, input: input)
        case "search_file":
            guard let rawPath = arguments["file_path"]?.stringValue else { throw ToolError.missingRequiredParameter("file_path") }
            let path = NSString(string: rawPath).expandingTildeInPath
            return try searchFile(regex: regex, path: path, pattern: pattern)
        case "replace":
            guard let input = arguments["input"]?.stringValue else { throw ToolError.missingRequiredParameter("input") }
            let replacement = arguments["replacement"]?.stringValue ?? ""
            return replaceInString(regex: regex, input: input, replacement: replacement)
        case "validate":
            let numGroups = regex.numberOfCaptureGroups
            return ToolResult(toolName: name, success: true,
                              output: "Pattern is valid. Capture groups: \(numGroups)")
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func matchString(regex: NSRegularExpression, input: String) -> ToolResult {
        let range = NSRange(input.startIndex..., in: input)
        let matches = regex.matches(in: input, range: range)
        if matches.isEmpty {
            return ToolResult(toolName: name, success: true, output: "No matches found.")
        }
        var lines: [String] = ["Matches (\(matches.count)):"]
        for (i, match) in matches.prefix(50).enumerated() {
            if let fullRange = Range(match.range, in: input) {
                lines.append("  [\(i)] '\(input[fullRange])'")
                for g in 1..<match.numberOfRanges {
                    if let groupRange = Range(match.range(at: g), in: input) {
                        lines.append("    group \(g): '\(input[groupRange])'")
                    }
                }
            }
        }
        return ToolResult(toolName: name, success: true, output: lines.joined(separator: "\n"))
    }

    private func searchFile(regex: NSRegularExpression, path: String, pattern: String) throws -> ToolResult {
        guard FileManager.default.fileExists(atPath: path) else {
            return ToolResult(toolName: name, success: false, output: "File not found: \(path)")
        }
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")
        var results: [String] = []
        for (lineNum, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            if regex.firstMatch(in: line, range: range) != nil {
                results.append("  \(lineNum + 1): \(line.prefix(200))")
            }
            if results.count >= 100 { break }
        }
        let output = results.isEmpty ? "No matches in \(path)" : "Matches in \(path) (\(results.count)):\n" + results.joined(separator: "\n")
        let truncated = output.count > 8_000 ? String(output.prefix(8_000)) + "\n... [truncated]" : output
        return ToolResult(toolName: name, success: true, output: truncated)
    }

    private func replaceInString(regex: NSRegularExpression, input: String, replacement: String) -> ToolResult {
        let range = NSRange(input.startIndex..., in: input)
        let result = regex.stringByReplacingMatches(in: input, range: range, withTemplate: replacement)
        return ToolResult(toolName: name, success: true,
                          output: "Result after replacement:\n\(result.prefix(10_000))")
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `NSRegularExpression` | ICU regex engine — Unicode-aware, supports capture groups, lookahead/lookbehind |

### Key Implementation Steps

1. **Pattern compilation** — compile the pattern once using `NSRegularExpression(pattern:options:)`. Return a validation error immediately if the pattern is invalid.
2. **match** — `regex.matches(in:range:)` returns all matches. Extract full match and named/numbered capture groups. Cap at 50 matches.
3. **search_file** — read file as UTF-8, split by newline, test each line. Report line numbers and content. Cap at 100 matching lines.
4. **replace** — `regex.stringByReplacingMatches` with a template. Supports `$0` (full match), `$1`–`$9` (groups).
5. **validate** — successfully compiled regex is valid; report capture group count.

### Output Truncation

`maxChars = 8_000` for file search; replacement output capped at 10,000 characters.

---

## Sandbox Entitlements

No additional entitlements required.

---

## Example Tool Calls

```json
{"tool": "regex", "arguments": {"action": "match", "pattern": "(\\w+)@(\\w+\\.\\w+)", "input": "Contact user@example.com or admin@test.org"}}
```

```json
{"tool": "regex", "arguments": {"action": "search_file", "pattern": "TODO|FIXME", "file_path": "~/Projects/my-app/Sources/ContentView.swift", "flags": "i"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| Invalid regex pattern | Returns `"Invalid regex pattern: <NSRegularExpression error>"` with `success: false` |
| Non-UTF-8 file | `String(contentsOfFile:)` throws; return `"Cannot read file as UTF-8"` |
| File not found | Returns `"File not found: <path>"` |

---

## Edge Cases

- **Very long lines** — truncate each matching line preview to 200 characters.
- **Binary files** — UTF-8 decoding will fail or produce garbage; return an error.
- **Catastrophic backtracking** — complex patterns on large inputs can hang. Consider adding a timeout via `Task.checkCancellation()` polling.

---

## See Also

- [DiffTool](./DiffTool.md)
- [JSONTransformTool](./JSONTransformTool.md)
- [FileSystemTool](../mlx-testing/AgentTools/FileSystemTool.swift) *(existing)*
