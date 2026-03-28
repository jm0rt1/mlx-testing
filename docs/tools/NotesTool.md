# NotesTool

**Category:** Productivity & Personal Data
**Risk Level:** medium
**Requires Approval:** Yes
**Tool Identifier:** `notes`

## Overview

`NotesTool` reads and writes Apple Notes via AppleScript. Listing note titles and reading note content are lower risk; creating and appending to notes modifies the Notes database and requires approval.

---

## Parameters

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `action` | string | Yes | — | One of `list`, `read`, `create`, `append`, `search` |
| `title` | string | No | — | Note title (for `read`, `create`, `append`) |
| `body` | string | No | — | Content to create or append |
| `folder` | string | No | — | Notes folder name |
| `query` | string | No | — | Search keyword (for `search`) |

---

## Swift Implementation

```swift
import Foundation

struct NotesTool: AgentTool {

    let name = "notes"
    let toolDescription = "Read and write Apple Notes via AppleScript: list, read, create, append text, and search notes."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "action", type: .string, description: "list | read | create | append | search",
                      required: true, enumValues: ["list", "read", "create", "append", "search"]),
        ToolParameter(name: "title",  type: .string, description: "Note title",             required: false),
        ToolParameter(name: "body",   type: .string, description: "Content to create/append", required: false),
        ToolParameter(name: "folder", type: .string, description: "Notes folder",           required: false),
        ToolParameter(name: "query",  type: .string, description: "Search keyword",         required: false),
    ]
    let requiresApproval = true
    let riskLevel: ToolRiskLevel = .medium

    func execute(arguments: [String: ToolArgumentValue]) async throws -> ToolResult {
        guard let action = arguments["action"]?.stringValue else { throw ToolError.missingRequiredParameter("action") }

        switch action {
        case "list":
            return runAppleScript("""
                tell application "Notes"
                    set result to ""
                    repeat with n in notes
                        set result to result & name of n & " | " & (modification date of n as string) & "\\n"
                    end repeat
                    result
                end tell
                """, maxChars: 5_000)

        case "read":
            guard let title = arguments["title"]?.stringValue else { throw ToolError.missingRequiredParameter("title") }
            return runAppleScript("""
                tell application "Notes"
                    set n to first note whose name contains "\(title)"
                    body of n
                end tell
                """, maxChars: 8_000)

        case "create":
            guard let title = arguments["title"]?.stringValue else { throw ToolError.missingRequiredParameter("title") }
            let body = arguments["body"]?.stringValue ?? ""
            let folder = arguments["folder"]?.stringValue
            let container = folder.map { "folder \"\($0)\" of account 1" } ?? "default account"
            return runAppleScript("""
                tell application "Notes"
                    tell \(container)
                        make new note with properties {name:"\(title)", body:"\(body.replacingOccurrences(of: "\"", with: "\\\""))"}
                    end tell
                end tell
                """)

        case "append":
            guard let title = arguments["title"]?.stringValue else { throw ToolError.missingRequiredParameter("title") }
            guard let body  = arguments["body"]?.stringValue  else { throw ToolError.missingRequiredParameter("body") }
            return runAppleScript("""
                tell application "Notes"
                    set n to first note whose name contains "\(title)"
                    set body of n to (body of n) & "\\n\(body.replacingOccurrences(of: "\"", with: "\\\""))"
                end tell
                """)

        case "search":
            guard let query = arguments["query"]?.stringValue else { throw ToolError.missingRequiredParameter("query") }
            return runAppleScript("""
                tell application "Notes"
                    set result to ""
                    set matches to every note whose name contains "\(query)" or body contains "\(query)"
                    repeat with n in matches
                        set result to result & name of n & "\\n"
                    end repeat
                    result
                end tell
                """, maxChars: 3_000)

        default:
            throw ToolError.executionFailed("Unknown action: \(action)")
        }
    }

    private func runAppleScript(_ script: String, maxChars: Int = 3_000) -> ToolResult {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&error)
        if let err = error { return ToolResult(toolName: name, success: false, output: "AppleScript error: \(err)") }
        var text = result?.stringValue ?? "(no output)"
        if text.count > maxChars { text = String(text.prefix(maxChars)) + "\n... [truncated]" }
        return ToolResult(toolName: name, success: true, output: text)
    }
}
```

---

## Sandbox Entitlements

| Entitlement | Purpose |
|---|---|
| `com.apple.security.automation.apple-events` | AppleScript to Notes.app (already present) |

---

## Example Tool Calls

```json
{"tool": "notes", "arguments": {"action": "search", "query": "WWDC"}}
```

```json
{"tool": "notes", "arguments": {"action": "create", "title": "Meeting notes", "body": "Discussed roadmap..."}}
```

---

## See Also

- [MailTool](./MailTool.md)
- [DreamJournalTool](./DreamJournalTool.md)
