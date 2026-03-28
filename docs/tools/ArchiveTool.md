# ArchiveTool

**Category:** Files & Documents
**Risk Level:** medium
**Requires Approval:** Yes
**Tool Identifier:** `archive`

## Overview

`ArchiveTool` creates and extracts ZIP archives and lists archive contents using Apple's `AppleArchive` framework or the `zip`/`unzip` system utilities. Listing is read-only; creation and extraction modify the file system and require approval.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `compress`, `extract`, `list` |
| `source_path` | string | No | — | File or directory to compress (for `compress`) |
| `archive_path` | string | Yes | — | Path to the archive file |
| `destination` | string | No | — | Directory to extract into (for `extract`) |

---

## Swift Implementation

```swift
import Foundation

struct ArchiveTool: AgentTool {

    let name = "archive"
    let toolDescription = "Create and extract ZIP archives. List archive contents without extracting."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action",       type: .string, description: "compress | extract | list",
                      required: true, enumValues: ["compress", "extract", "list"]),
        ToolParameter(name: "source_path",  type: .string, description: "Source file/directory to compress", required: false),
        ToolParameter(name: "archive_path", type: .string, description: "ZIP archive file path",              required: true),
        ToolParameter(name: "destination",  type: .string, description: "Extraction destination directory",   required: false),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else { throw ToolError.missingRequiredParameter("action") }
        guard let rawArchive = arguments["archive_path"]?.stringValue else { throw ToolError.missingRequiredParameter("archive_path") }
        let archivePath = NSString(string: rawArchive).expandingTildeInPath

        switch action {
        case "compress":
            guard let rawSrc = arguments["source_path"]?.stringValue else { throw ToolError.missingRequiredParameter("source_path") }
            let srcPath = NSString(string: rawSrc).expandingTildeInPath
            return runShell(["zip", "-r", archivePath, srcPath])
        case "extract":
            let dest: String
            if let rawDest = arguments["destination"]?.stringValue {
                dest = NSString(string: rawDest).expandingTildeInPath
            } else {
                dest = (archivePath as NSString).deletingPathExtension
            }
            return runShell(["unzip", "-o", archivePath, "-d", dest])
        case "list":
            return runShell(["unzip", "-l", archivePath], maxChars: 8_000)
        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    // MARK: - Helper

    private func runShell(_ args: [String], maxChars: Int = 5_000) -> ToolResult {
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
| `zip` / `unzip` system binaries | ZIP creation, extraction, and listing |
| `AppleArchive` framework (macOS 11+) | Native alternative for `.aar` archives |

### Key Implementation Steps

1. **compress** — `zip -r <archive> <source>` to create a ZIP recursively.
2. **extract** — `unzip -o <archive> -d <dest>` to extract with overwrite. Default destination is the archive name without extension.
3. **list** — `unzip -l <archive>` prints the file manifest without extracting.

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` | Read/write archives and sources under `~` |

---

## Example Tool Calls

```json
{"tool": "archive", "arguments": {"action": "list", "archive_path": "~/Downloads/release.zip"}}
```

```json
{"tool": "archive", "arguments": {"action": "compress", "source_path": "~/Projects/my-app", "archive_path": "~/Desktop/my-app.zip"}}
```

---

## See Also

- [FileSystemTool](../mlx-testing/AgentTools/FileSystemTool.swift) *(existing)*
- [PDFTool](./PDFTool.md)
