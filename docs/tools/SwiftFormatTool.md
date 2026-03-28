# SwiftFormatTool

**Category:** Developer Productivity
**Risk Level:** medium
**Requires Approval:** Yes
**Tool Identifier:** `swift_format`

## Overview

`SwiftFormatTool` formats and lints Swift source files using `swift-format` or `swiftlint`. The `lint` action is read-only (low risk). The `format` action modifies files on disk (medium risk, requires approval). A `diff` action is available to preview changes without writing them, enabling the LLM to review formatting suggestions before applying.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `lint`, `format`, `diff` |
| `path` | string | Yes | — | File or directory path to lint/format |
| `tool` | string | No | `"swift-format"` | Formatting tool: `swift-format` or `swiftlint` |
| `config_path` | string | No | — | Path to `.swift-format` or `.swiftlint.yml` config file |

---

## Swift Implementation

```swift
import Foundation

struct SwiftFormatTool: AgentTool {

    let name = "swift_format"
    let toolDescription = "Lint and format Swift source files using swift-format or swiftlint."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",      type: .string, description: "lint | format | diff",
                      required: true, enumValues: ["lint", "format", "diff"]),
        ToolParameter(name: "path",        type: .string, description: "File or directory path",   required: true),
        ToolParameter(name: "tool",        type: .string, description: "swift-format | swiftlint",
                      required: false, defaultValue: "swift-format",
                      enumValues: ["swift-format", "swiftlint"]),
        ToolParameter(name: "config_path", type: .string, description: "Config file path",         required: false),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action     = arguments["action"]?.stringValue   else { throw ToolError.missingRequiredParameter("action") }
        guard let rawPath    = arguments["path"]?.stringValue     else { throw ToolError.missingRequiredParameter("path") }
        let toolName  = arguments["tool"]?.stringValue ?? "swift-format"
        let configPath = arguments["config_path"]?.stringValue
        let path = NSString(string: rawPath).expandingTildeInPath

        switch (action, toolName) {
        case ("lint", "swift-format"):
            var cmd = ["swift-format", "lint", "--recursive", path]
            if let cfg = configPath { cmd += ["--configuration", cfg] }
            return run(cmd, maxChars: 10_000)

        case ("format", "swift-format"):
            var cmd = ["swift-format", "format", "--in-place", "--recursive", path]
            if let cfg = configPath { cmd += ["--configuration", cfg] }
            return run(cmd)

        case ("diff", "swift-format"):
            // Run format to stdout (no --in-place), then diff against original
            var cmd = ["swift-format", "format", "--recursive", path]
            if let cfg = configPath { cmd += ["--configuration", cfg] }
            return run(cmd, maxChars: 12_000)

        case ("lint", "swiftlint"):
            var cmd = ["swiftlint", "lint", path]
            if let cfg = configPath { cmd += ["--config", cfg] }
            return run(cmd, maxChars: 10_000)

        case ("format", "swiftlint"):
            var cmd = ["swiftlint", "--fix", path]
            if let cfg = configPath { cmd += ["--config", cfg] }
            return run(cmd)

        default:
            throw ToolError.executionFailed("Unknown action/tool combination: \(action)/\(toolName)")
        }
    }

    // MARK: - Helper

    private func run(_ args: [String], maxChars: Int = 8_000) -> ToolResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/usr/local/bin:/opt/homebrew/bin"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        try? p.run(); p.waitUntilExit()
        var output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if output.isEmpty { output = "(No output — formatting may have been applied silently)" }
        if output.count > maxChars { output = String(output.prefix(maxChars)) + "\n... [truncated]" }
        return ToolResult(toolName: name, success: p.terminationStatus == 0, output: output)
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `swift-format` CLI (Apple) | Official Swift code formatter; install via `brew install swift-format` |
| `swiftlint` CLI (Realm) | Lint rules and auto-fix; install via `brew install swiftlint` |
| `Process` | Shell out to whichever tool is installed |

### Key Implementation Steps

1. **lint** — run with `--recursive` for directories. Parse exit code: `0` = no violations, `1` = violations found.
2. **format** — run with `--in-place --recursive`. swift-format modifies files silently on success.
3. **diff** — run `swift-format format` without `--in-place` (prints formatted output to stdout), then use `DiffTool` logic to show what would change. Alternatively shell to `diff -u <original> <formatted>`.
4. **Config discovery** — if no `config_path` provided, both tools look for their config in the current directory and parent directories. Pass `path`'s directory as the working directory.

### Output Truncation

`maxChars = 10_000` for lint output; `12_000` for diffs.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | Read/write Swift files under `~` |

---

## Example Tool Calls

```json
{"tool": "swift_format", "arguments": {"action": "lint", "path": "~/Projects/my-app/Sources"}}
```

```json
{"tool": "swift_format", "arguments": {"action": "format", "path": "~/Projects/my-app/Sources/ContentView.swift"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| `swift-format` not installed | Process launch fails; return message with `brew install swift-format` |
| `swiftlint` not installed | Same pattern with `brew install swiftlint` |
| Path does not exist | Tool exits with error; propagated in output |

---

## Edge Cases

- **Mixed project** — `swift-format` and `swiftlint` use different rule sets; running both may produce conflicting suggestions.
- **Generated files** — exclude `*.generated.swift` files by adding them to `.swiftlint.yml`'s `excluded` list.
- **Large codebases** — `--recursive` on a large project directory can produce thousands of lint lines; truncation kicks in at `maxChars`.

---

## See Also

- [DiffTool](./DiffTool.md)
- [XcodeTool](./XcodeTool.md)
- [GitTool](./GitTool.md)
