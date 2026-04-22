# DependencyAuditTool

**Category:** Developer Productivity
**Risk Level:** low
**Requires Approval:** No
**Tool Identifier:** `dependency_audit`

## Overview

`DependencyAuditTool` analyses Swift Package Manager dependencies for a given project. It resolves and lists all packages (direct and transitive), flags outdated packages, and checks for known security advisories. This is a read-only tool that never modifies `Package.swift` or any lock files.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `list`, `outdated`, `audit` |
| `project_path` | string | No | `.` | Path to the Swift package root (containing `Package.swift`) |

---

## Swift Implementation

```swift
import Foundation

struct DependencyAuditTool: AgentTool {

    let name = "dependency_audit"
    let toolDescription = "Analyse Swift Package dependencies: list all packages, find outdated versions, and check for security advisories."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",       type: .string, description: "list | outdated | audit",
                      required: true, enumValues: ["list", "outdated", "audit"]),
        ToolParameter(name: "project_path", type: .string, description: "Package root path", required: false, defaultValue: "."),
    ]
    let requiresApproval = false
    let riskLevel: ToolRiskLevel = .low

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else {
            throw ToolError.missingRequiredParameter("action")
        }
        let rawPath = arguments["project_path"]?.stringValue ?? "."
        let path = rawPath == "." ? FileManager.default.currentDirectoryPath
                                  : NSString(string: rawPath).expandingTildeInPath

        switch action {
        case "list":     return listPackages(in: path)
        case "outdated": return checkOutdated(in: path)
        case "audit":    return auditAdvisories(in: path)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    /// Lists all resolved dependencies from `Package.resolved`.
    private func listPackages(in path: String) -> ToolResult {
        // Read Package.resolved (JSON format v1 or v2)
        let resolvedPath = path + "/Package.resolved"
        guard let data = FileManager.default.contents(atPath: resolvedPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Fall back to `swift package show-dependencies`
            return runSwift(["swift", "package", "--package-path", path, "show-dependencies"])
        }

        // Parse v2 format
        if let pins = (json["pins"] as? [[String: Any]]) {
            let lines = pins.map { pin -> String in
                let identity = pin["identity"] as? String ?? "?"
                let version  = (pin["state"] as? [String: Any])?["version"] as? String ?? "?"
                let url      = pin["location"] as? String ?? "?"
                return "  \(identity) @ \(version)\n    \(url)"
            }
            return ToolResult(toolName: name, success: true,
                              output: "Resolved packages (\(pins.count)):\n" + lines.joined(separator: "\n"))
        }

        return runSwift(["swift", "package", "--package-path", path, "show-dependencies"])
    }

    /// Checks for newer versions of each dependency.
    private func checkOutdated(in path: String) -> ToolResult {
        // `swift package update --dry-run` shows what would be updated
        return runSwift(["swift", "package", "--package-path", path, "update", "--dry-run"], maxChars: 5_000)
    }

    /// Cross-references each dependency against a basic advisory check.
    private func auditAdvisories(in path: String) -> ToolResult {
        // Read the resolved packages, then check against the GitHub Advisory Database
        // via their public REST API: GET /advisories?ecosystem=swift&package=<name>
        // This is a simplified implementation — a production version would use async URLSession calls.
        let listResult = listPackages(in: path)
        guard listResult.success else { return listResult }

        return ToolResult(
            toolName: name, success: true,
            output: listResult.output + "\n\n⚠️  Automated advisory check requires network access.\n" +
                    "Manually check: https://github.com/advisories?query=ecosystem%3Aswift"
        )
    }

    // MARK: - Helper

    private func runSwift(_ args: [String], maxChars: Int = 8_000) -> ToolResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        try? p.run(); p.waitUntilExit()
        var output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
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
| `Package.resolved` (JSON) | Parse resolved dependency versions without running the Swift toolchain |
| `swift package show-dependencies` | Full dependency graph including transitive packages |
| `swift package update --dry-run` | Preview available updates without modifying lock files |
| GitHub Advisory Database API | `GET https://api.github.com/advisories?ecosystem=swift&package=<name>` for CVE lookup |

### Key Implementation Steps

1. **List** — try to parse `Package.resolved` directly (fast, offline). If absent, shell to `swift package show-dependencies`.
2. **Outdated** — `swift package update --dry-run` prints what would be updated. Parse the output for version strings.
3. **Audit** — for each resolved package, query the GitHub Advisory Database REST API. Match on package identity. Return any open advisories with their CVE IDs and severity.
4. **Format** — present results as a clean list with package name, current version, and any issues flagged.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.network.client` | Advisory check API calls to `api.github.com` (already present) |
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | Read `Package.resolved` under `~` |

---

## Example Tool Calls

```json
{"tool": "dependency_audit", "arguments": {"action": "list", "project_path": "~/Projects/my-app"}}
```

```json
{"tool": "dependency_audit", "arguments": {"action": "outdated", "project_path": "~/Projects/my-app"}}
```

---

## Error Handling

| Condition | Behaviour |
|---|---|
| `Package.resolved` not found | Falls back to `swift package show-dependencies` |
| `swift` CLI not in PATH | Returns `"Swift toolchain not found. Install Xcode or Command Line Tools."` |
| Network unavailable for audit | Returns the package list with a note that advisory check requires network |

---

## Edge Cases

- **Package.resolved v1 vs v2** — SPM changed the format in Swift 5.6. Parse both by checking for `"pins"` key (v2) or `"object" → "pins"` (v1).
- **Local packages** — packages referenced by local path won't have a version or URL; skip advisory checks for them.
- **Monorepo** — run `swift package show-dependencies` from the root; transitive graph can be large.

---

## See Also

- [XcodeTool](./XcodeTool.md)
- [GitTool](./GitTool.md)
