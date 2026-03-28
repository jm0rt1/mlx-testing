# DiffTool

**Category:** Developer Productivity
**Risk Level:** low
**Requires Approval:** No
**Tool Identifier:** `diff`

## Overview

`DiffTool` computes diffs between two strings or two file paths and returns a unified diff. It also supports word-level diffs for prose and directory-level diffs. All operations are read-only and safe for automatic execution.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `strings`, `files`, `word`, `directories` |
| `before` | string | No | — | "Before" string or file/directory path |
| `after` | string | No | — | "After" string or file/directory path |

---

## Swift Implementation

```swift
import Foundation

struct DiffTool: AgentTool {

    let name = "diff"
    let toolDescription = "Compute unified diffs between strings, files, or directories. Supports word-level diffs for prose."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action", type: .string,
                      description: "strings | files | word | directories",
                      required: true, enumValues: ["strings", "files", "word", "directories"]),
        ToolParameter(name: "before", type: .string, description: "Before text, file, or directory path", required: true),
        ToolParameter(name: "after",  type: .string, description: "After text, file, or directory path",  required: true),
    ]
    let requiresApproval = false
    let riskLevel: ToolRiskLevel = .low

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else { throw ToolError.missingRequiredParameter("action") }
        guard let before = arguments["before"]?.stringValue else { throw ToolError.missingRequiredParameter("before") }
        guard let after  = arguments["after"]?.stringValue  else { throw ToolError.missingRequiredParameter("after") }

        switch action {
        case "strings":     return diffStrings(before: before, after: after)
        case "files":       return diffFiles(before: before, after: after)
        case "word":        return wordDiff(before: before, after: after)
        case "directories": return directoryDiff(before: before, after: after)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func diffStrings(before: String, after: String) -> ToolResult {
        // Write both strings to temp files and diff them
        let dir = FileManager.default.temporaryDirectory
        let beforeURL = dir.appendingPathComponent("diff_before_\(UUID().uuidString).txt")
        let afterURL  = dir.appendingPathComponent("diff_after_\(UUID().uuidString).txt")
        do {
            try before.write(to: beforeURL, atomically: true, encoding: .utf8)
            try after.write(to: afterURL,   atomically: true, encoding: .utf8)
        } catch {
            return ToolResult(toolName: name, success: false, output: "Could not write temp files: \(error)")
        }
        defer {
            try? FileManager.default.removeItem(at: beforeURL)
            try? FileManager.default.removeItem(at: afterURL)
        }
        return runDiff(before: beforeURL.path, after: afterURL.path)
    }

    private func diffFiles(before: String, after: String) -> ToolResult {
        let b = NSString(string: before).expandingTildeInPath
        let a = NSString(string: after).expandingTildeInPath
        return runDiff(before: b, after: a)
    }

    private func wordDiff(before: String, after: String) -> ToolResult {
        // Use `diff --word-diff` via shell
        let dir = FileManager.default.temporaryDirectory
        let bURL = dir.appendingPathComponent("wdiff_b_\(UUID().uuidString).txt")
        let aURL = dir.appendingPathComponent("wdiff_a_\(UUID().uuidString).txt")
        try? before.write(to: bURL, atomically: true, encoding: .utf8)
        try? after.write(to: aURL,  atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: bURL)
            try? FileManager.default.removeItem(at: aURL)
        }
        return runShell(["diff", "--word-diff=color", bURL.path, aURL.path])
    }

    private func directoryDiff(before: String, after: String) -> ToolResult {
        let b = NSString(string: before).expandingTildeInPath
        let a = NSString(string: after).expandingTildeInPath
        return runShell(["diff", "-rq", b, a], maxChars: 8_000)
    }

    // MARK: - Helpers

    private func runDiff(before: String, after: String) -> ToolResult {
        return runShell(["diff", "-u", before, after], maxChars: 12_000)
    }

    private func runShell(_ args: [String], maxChars: Int = 8_000) -> ToolResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
        p.arguments = Array(args.dropFirst())  // skip "diff" since we set the executable
        if args.first != "diff" {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = args
        }
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run(); p.waitUntilExit()
        var output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // diff exits with 0 if identical, 1 if different, 2 on error
        if p.terminationStatus == 0 { output = "(files are identical)" }
        if output.count > maxChars { output = String(output.prefix(maxChars)) + "\n... [truncated]" }
        return ToolResult(toolName: name, success: p.terminationStatus <= 1, output: output)
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `/usr/bin/diff` system binary | Unified and word diffs |
| `FileManager.temporaryDirectory` | Write string inputs to temp files for diffing |

### Key Implementation Steps

1. **strings** — write both strings to unique temp files in `FileManager.temporaryDirectory`, run `diff -u`, clean up temp files.
2. **files** — resolve `~` paths, run `diff -u` directly on the file paths.
3. **word** — use `diff --word-diff=color` for prose-level diffs.
4. **directories** — `diff -rq` reports only which files differ; `diff -r` would show full diffs (too verbose for large directories).
5. **Exit code** — `diff` exits `0` if identical, `1` if different, `2` on error. Mark `success: true` for both 0 and 1.

### Output Truncation

`maxChars = 12_000` for file and string diffs; 8,000 for directory diffs.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | Read files under `~` for comparison; write temp files |

---

## Example Tool Calls

```json
{"tool": "diff", "arguments": {"action": "strings", "before": "hello world", "after": "hello Swift"}}
```

```json
{"tool": "diff", "arguments": {"action": "files", "before": "~/old.swift", "after": "~/new.swift"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| Files identical | Returns `"(files are identical)"` with `success: true` |
| File not found | `diff` exits with code 2; return shell error |
| Binary files | `diff` reports `"Binary files differ"`; return that message |

---

## See Also

- [GitTool](./GitTool.md)
- [RegexTool](./RegexTool.md)
