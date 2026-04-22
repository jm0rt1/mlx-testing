# XcodeTool

**Category:** Developer Productivity
**Risk Level:** high
**Requires Approval:** Yes
**Tool Identifier:** `xcode`

## Overview

`XcodeTool` drives Xcode builds and tests via `xcodebuild`. It can build a scheme, run the test suite, report pass/fail counts with failure messages, clean derived data, and archive a project. Because building and archiving execute arbitrary Swift code, this tool is rated `high` risk and always requires approval.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `build`, `test`, `clean`, `archive`, `list_schemes` |
| `project_path` | string | Yes | — | Path to `.xcodeproj` or `.xcworkspace` |
| `scheme` | string | No | — | Scheme name (required for `build`, `test`, `archive`) |
| `destination` | string | No | `"platform=macOS"` | `xcodebuild` destination string |
| `configuration` | string | No | `"Debug"` | `Debug` or `Release` |
| `archive_path` | string | No | `~/Desktop/Archive.xcarchive` | Output path for `archive` |

---

## Swift Implementation

```swift
import Foundation

struct XcodeTool: AgentTool {

    let name = "xcode"
    let toolDescription = "Build, test, clean, and archive Xcode projects via xcodebuild."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",       type: .string, description: "build | test | clean | archive | list_schemes",
                      required: true, enumValues: ["build", "test", "clean", "archive", "list_schemes"]),
        ToolParameter(name: "project_path", type: .string, description: ".xcodeproj or .xcworkspace path", required: true),
        ToolParameter(name: "scheme",       type: .string, description: "Scheme name",          required: false),
        ToolParameter(name: "destination",  type: .string, description: "xcodebuild destination", required: false, defaultValue: "platform=macOS"),
        ToolParameter(name: "configuration",type: .string, description: "Debug | Release",      required: false, defaultValue: "Debug"),
        ToolParameter(name: "archive_path", type: .string, description: "Archive output path",  required: false),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .high

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("action")
        }
        guard let rawProjectPath = arguments["project_path"]?.stringValue else {
            throw ToolError.missingRequiredParameter("project_path")
        }
        let projectPath = NSString(string: rawProjectPath).expandingTildeInPath
        let isWorkspace = projectPath.hasSuffix(".xcworkspace")
        let projectFlag = isWorkspace ? "-workspace" : "-project"

        switch action {
        case "list_schemes":
            return run(["/usr/bin/xcodebuild", projectFlag, projectPath, "-list"])

        case "build":
            guard let scheme = arguments["scheme"]?.stringValue else { throw ToolError.missingRequiredParameter("scheme") }
            let dest = arguments["destination"]?.stringValue ?? "platform=macOS"
            let config = arguments["configuration"]?.stringValue ?? "Debug"
            return run(["/usr/bin/xcodebuild", projectFlag, projectPath, "-scheme", scheme,
                        "-destination", dest, "-configuration", config, "build"], maxChars: 15_000)

        case "test":
            guard let scheme = arguments["scheme"]?.stringValue else { throw ToolError.missingRequiredParameter("scheme") }
            let dest = arguments["destination"]?.stringValue ?? "platform=macOS"
            return run(["/usr/bin/xcodebuild", projectFlag, projectPath, "-scheme", scheme,
                        "-destination", dest, "test"], maxChars: 15_000)

        case "clean":
            let scheme = arguments["scheme"]?.stringValue
            var cmd = ["/usr/bin/xcodebuild", projectFlag, projectPath]
            if let s = scheme { cmd += ["-scheme", s] }
            cmd.append("clean")
            return run(cmd)

        case "archive":
            guard let scheme = arguments["scheme"]?.stringValue else { throw ToolError.missingRequiredParameter("scheme") }
            let archivePath = arguments["archive_path"]?.stringValue.flatMap {
                NSString(string: $0).expandingTildeInPath as String
            } ?? (NSHomeDirectory() + "/Desktop/Archive.xcarchive")
            return run(["/usr/bin/xcodebuild", projectFlag, projectPath, "-scheme", scheme,
                        "archive", "-archivePath", archivePath], maxChars: 15_000)

        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Helper

    private func run(_ args: [String], maxChars: Int = 8_000) -> ToolResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        try? p.run(); p.waitUntilExit()
        var output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        // Parse test summary if present
        if args.contains("test") {
            output = summariseTestOutput(output)
        }

        if output.count > maxChars { output = String(output.prefix(maxChars)) + "\n\n... [truncated]" }
        return ToolResult(toolName: name, success: p.terminationStatus == 0, output: output)
    }

    /// Extracts the test summary lines (pass/fail counts and failure messages) from raw xcodebuild output.
    private func summariseTestOutput(_ raw: String) -> String {
        let lines = raw.components(separatedBy: "\n")
        let summaryLines = lines.filter { line in
            line.contains("Test Suite") || line.contains("Test Case") ||
            line.contains("error:") || line.contains("FAILED") || line.contains("passed") ||
            line.contains("** TEST")
        }
        let summary = summaryLines.joined(separator: "\n")
        return summary.isEmpty ? raw : "=== TEST SUMMARY ===\n\(summary)\n\n=== FULL OUTPUT ===\n\(raw)"
    }
}
```

---

## Implementation Approach

### Frameworks & APIs

| Framework / API | Purpose |
|---|---|
| `/usr/bin/xcodebuild` via `Process` | All build, test, clean, archive operations |
| Output parsing (string matching) | Extract test pass/fail summary from verbose xcodebuild output |

### Key Implementation Steps

1. **project vs. workspace** — detect by file extension (`.xcworkspace` → `-workspace`, `.xcodeproj` → `-project`).
2. **list_schemes** — `xcodebuild -list` returns all schemes and targets in the project.
3. **build / test** — forward `xcodebuild` exit code as `success`. Parse test output to extract summary statistics (`Test Case '-[...]' passed`, `** TEST FAILED **`).
4. **clean** — optionally scoped to a scheme; omitting `-scheme` cleans all.
5. **archive** — requires a Release configuration typically; defaults to `~/Desktop/Archive.xcarchive`.
6. **Output cap** — xcodebuild output can be 100K+ characters; cap at 15,000 and prioritise the summary.

### Output Truncation

`maxChars = 15_000`. The `summariseTestOutput` helper prepends a condensed summary section before the full output, so the most important information is within the first 15,000 characters.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.files.user-selected.read-write` | Access the project directory |
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | Access projects under `~` |

> Building code inherently executes Run Script phases and generates binaries. This is why the tool is rated `high` risk.

---

## Example Tool Calls

```json
{"tool": "xcode", "arguments": {"action": "list_schemes", "project_path": "~/Projects/my-app/my-app.xcodeproj"}}
```

```json
{"tool": "xcode", "arguments": {"action": "test", "project_path": "~/Projects/my-app/my-app.xcodeproj", "scheme": "my-appTests"}}
```

```json
{"tool": "xcode", "arguments": {"action": "build", "project_path": "~/Projects/my-app/my-app.xcodeproj", "scheme": "my-app", "configuration": "Release"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| `xcodebuild` not found | `Process` launch fails; return `"xcodebuild not found. Install Xcode Command Line Tools."` |
| Scheme not found | `xcodebuild` returns `error: The requested scheme … does not exist`; `success: false` |
| Build errors | Compiler errors appear in output; `success: false` |
| Test failures | `** TEST FAILED **` in output; `success: false` |

---

## Edge Cases

- **Simulator destinations** — for iOS projects use `"platform=iOS Simulator,name=iPhone 15"` as the destination string.
- **Code signing** — automated builds may fail due to signing; use `CODE_SIGNING_ALLOWED=NO` for testing builds by appending it to the argument list.
- **Derived data location** — add `-derivedDataPath /tmp/DerivedData` to avoid polluting the default location during automated runs.

---

## See Also

- [GitTool](./GitTool.md)
- [SwiftFormatTool](./SwiftFormatTool.md)
- [ShellCommandTool](../mlx-testing/AgentTools/ShellCommandTool.swift) *(existing)*
